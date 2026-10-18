#!/usr/bin/env python3
"""Report and remove idle, regenerable build output left in temporary space.

Each sweep kind recognizes one kind of build output, such as a Cargo target
directory. A matched directory is removed only when nothing in it was written
within `--idle-for`, none of its build locks are held, and no running process
has its executable or working directory inside it.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import functools
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import time
from collections.abc import Callable, Generator, Sequence
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Literal, cast


EXIT_OK = 0
EXIT_REMOVAL_FAILED = 1
EXIT_USAGE = 2


def main(
    argv: list[str] | None = None, list_processes: ProcessLister | None = None
) -> int:
    """Run the command line and return its exit status.

    `list_processes` replaces the live process listing; tests inject one so
    they never run `ps` or `lsof`.
    """
    args = parse_args(argv)
    kinds = [SWEEP_KINDS[name] for name in args.kind_names]

    if len(args.roots) > 0:
        missing = [root for root in args.roots if not root.is_dir()]
        if len(missing) > 0:
            for root in missing:
                print(f"error: root is not a directory: {root}", file=sys.stderr)
            return EXIT_USAGE
        roots = scan_roots(args.roots)
    else:
        roots = scan_roots([root for kind in kinds for root in kind.default_roots()])

    sweep = Sweep(
        kinds=kinds,
        idle_for_seconds=args.idle_for_seconds,
        list_processes=list_process_paths if list_processes is None else list_processes,
    )
    if args.command == "report":
        return report(roots, sweep)
    return clean(roots, sweep)


@dataclass(frozen=True)
class Args:
    command: Literal["report", "clean"]
    kind_names: tuple[str, ...]
    idle_for_seconds: int
    roots: tuple[Path, ...]


def parse_args(argv: list[str] | None = None) -> Args:
    """Parse the command line; argparse exits with status 2 on usage errors."""
    namespace = create_parser().parse_args(argv)
    kind_names = cast(list[str] | None, namespace.kind)
    return Args(
        command=cast(Literal["report", "clean"], namespace.command),
        kind_names=tuple(
            dict.fromkeys(SWEEP_KINDS if kind_names is None else kind_names)
        ),
        idle_for_seconds=cast(int, namespace.idle_for),
        roots=tuple(Path(root) for root in cast(list[str], namespace.roots)),
    )


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="scratch-sweep",
        description=(
            "Report and remove idle build output, such as Cargo target "
            "directories, left in temporary directories."
        ),
        epilog=(
            "Without ROOT, scans /tmp/agent-$UID, /tmp/claude-$UID, and the "
            "system user temp directory. Only matched build directories are "
            "removed; other files are never touched."
        ),
    )
    subparsers = parser.add_subparsers(dest="command", metavar="COMMAND", required=True)
    commands = {
        "report": "list build directories and what clean would do; deletes nothing",
        "clean": "remove build directories that are idle and not in use",
    }
    for name, help_text in commands.items():
        command_parser = subparsers.add_parser(name, help=help_text)
        _ = command_parser.add_argument(
            "--idle-for",
            type=idle_duration_seconds,
            default=0,
            metavar="DURATION",
            help=(
                "skip build directories with any entry written within DURATION "
                "(0 or <int>{s,m,h,d}; default 0)"
            ),
        )
        _ = command_parser.add_argument(
            "--kind",
            action="append",
            choices=list(SWEEP_KINDS),
            help="limit the run to this sweep kind (repeatable; default: all kinds)",
        )
        _ = command_parser.add_argument(
            "roots",
            nargs="*",
            metavar="ROOT",
            help="scan these directories instead of the default roots",
        )
    return parser


DURATION_UNIT_SECONDS = {"s": 1, "m": 60, "h": 3600, "d": 86400}


def idle_duration_seconds(value: str) -> int:
    """Parse an `--idle-for` duration, `0` or `<int>{s,m,h,d}`, into seconds."""
    if value == "0":
        return 0
    match = re.fullmatch(r"([0-9]+)([smhd])", value)
    if match is None:
        raise argparse.ArgumentTypeError("must be 0 or <int>{s,m,h,d}, such as 2h")
    return int(match.group(1)) * DURATION_UNIT_SECONDS[match.group(2)]


def scan_roots(candidates: Sequence[Path]) -> list[Path]:
    """Resolve candidate roots, dropping missing ones and roots nested in others.

    Roots are resolved so their paths compare equal to the real paths that
    process listings report, such as `/private/tmp` for `/tmp` on macOS.
    """
    resolved = sorted(
        {candidate.resolve() for candidate in candidates if candidate.is_dir()}
    )
    roots: list[Path] = []
    for root in resolved:
        if not any(is_inside(str(root), str(kept)) for kept in roots):
            roots.append(root)
    return roots


def is_inside(path: str, directory: str) -> bool:
    return path == directory or path.startswith(directory.rstrip(os.sep) + os.sep)


# Running a sweep


@dataclass(frozen=True)
class Sweep:
    """The settings one `report` or `clean` run applies to every build directory."""

    kinds: Sequence[SweepKind]
    idle_for_seconds: int
    list_processes: ProcessLister


@dataclass(frozen=True)
class BuildDir:
    path: Path
    kind: SweepKind


@dataclass(frozen=True)
class BuildDirUsage:
    """Disk use and activity of one build directory.

    `allocated_bytes` counts allocated blocks, with hard links counted once.
    `last_activity` is the newest `lstat` mtime of any entry, directories
    included, in seconds since the epoch.
    """

    allocated_bytes: int
    last_activity: float


def report(roots: Sequence[Path], sweep: Sweep) -> int:
    """Print every build directory under `roots` with what `clean` would do."""
    build_dirs = find_build_dirs(roots, sweep.kinds)
    if len(build_dirs) == 0:
        print(f"No build directories found under: {format_roots(roots)}")
        return EXIT_OK

    # One process snapshot serves the whole report; clean takes a fresh one
    # for each directory while holding its locks.
    list_processes = functools.cache(sweep.list_processes)
    removable_bytes = 0
    removable_count = 0
    total_bytes = 0
    now = time.time()
    for build_dir in build_dirs:
        try:
            usage = measure_usage(build_dir.path)
        except OSError as error:
            name = build_dir.kind.name
            print(f"skip {build_dir.path} ({name}): cannot measure: {error}")
            continue
        total_bytes += usage.allocated_bytes

        reason = idle_skip_reason(usage, sweep.idle_for_seconds, now)
        if reason is None:
            with holding_locks(build_dir) as lock_failure:
                reason = lock_failure
        if reason is None:
            reason = process_skip_reason(build_dir, list_processes)

        description = describe(build_dir, usage, now)
        if reason is None:
            removable_bytes += usage.allocated_bytes
            removable_count += 1
            print(f"would remove {description}")
        else:
            print(f"skip {description}: {reason}")

    print(
        f"\n{count_build_dirs(len(build_dirs))}, {format_bytes(total_bytes)}; "
        + f"clean would remove {removable_count} ({format_bytes(removable_bytes)})"
    )
    return EXIT_OK


def clean(roots: Sequence[Path], sweep: Sweep) -> int:
    """Remove every idle, unused build directory under `roots`.

    Returns 1 when any removal failed after its directory was renamed away,
    otherwise 0. Skipped directories are not failures.
    """
    build_dirs = find_build_dirs(roots, sweep.kinds)
    if len(build_dirs) == 0:
        print(f"No build directories found under: {format_roots(roots)}")
        return EXIT_OK

    freed_bytes = 0
    removed_count = 0
    skipped_count = 0
    failed_count = 0
    for build_dir in build_dirs:
        outcome = remove_build_dir(build_dir, sweep)
        if isinstance(outcome, Removed):
            freed_bytes += outcome.usage.allocated_bytes
            removed_count += 1
            print(f"removed {outcome.description}")
        elif isinstance(outcome, Skipped):
            skipped_count += 1
            print(f"skip {outcome.description}: {outcome.reason}")
        else:
            failed_count += 1
            print(
                f"error: could not remove {outcome.description}: {outcome.error}; "
                + f"remaining files are in {outcome.renamed_path}",
                file=sys.stderr,
            )

    print(
        f"\nFreed {format_bytes(freed_bytes)} from {count_build_dirs(removed_count)}; "
        + f"{skipped_count} skipped, {failed_count} failed"
    )
    return EXIT_REMOVAL_FAILED if failed_count > 0 else EXIT_OK


@dataclass(frozen=True)
class Removed:
    description: str
    usage: BuildDirUsage


@dataclass(frozen=True)
class Skipped:
    description: str
    reason: str


@dataclass(frozen=True)
class RemovalFailed:
    """The directory was renamed away but could not be fully deleted."""

    description: str
    error: OSError
    renamed_path: Path


def remove_build_dir(
    build_dir: BuildDir, sweep: Sweep
) -> Removed | Skipped | RemovalFailed:
    """Remove one build directory if it is idle and not in use.

    The kind's locks are held while the directory is checked for running
    processes and renamed to a hidden sibling, so a build that starts
    meanwhile waits for the locks rather than writing into a half-deleted
    tree. The renamed directory is deleted after the locks are released.
    """
    now = time.time()
    try:
        usage = measure_usage(build_dir.path)
    except OSError as error:
        return Skipped(
            description=f"{build_dir.path} ({build_dir.kind.name})",
            reason=f"cannot measure: {error}",
        )
    description = describe(build_dir, usage, now)

    reason = idle_skip_reason(usage, sweep.idle_for_seconds, now)
    if reason is not None:
        return Skipped(description=description, reason=reason)

    renamed_path = build_dir.path.parent / f".scratch-sweep-{secrets.token_hex(8)}"
    with holding_locks(build_dir) as lock_failure:
        if lock_failure is not None:
            return Skipped(description=description, reason=lock_failure)

        reason = process_skip_reason(build_dir, sweep.list_processes)
        if reason is not None:
            return Skipped(description=description, reason=reason)

        try:
            _ = build_dir.path.rename(renamed_path)
        except OSError as error:
            return Skipped(description=description, reason=f"cannot rename: {error}")

    try:
        shutil.rmtree(renamed_path)
    except OSError as error:
        return RemovalFailed(
            description=description, error=error, renamed_path=renamed_path
        )
    return Removed(description=description, usage=usage)


def idle_skip_reason(
    usage: BuildDirUsage, idle_for_seconds: int, now: float
) -> str | None:
    if idle_for_seconds == 0:
        return None
    idle_seconds = now - usage.last_activity
    if idle_seconds >= idle_for_seconds:
        return None
    written_ago = format_age(idle_seconds)
    return (
        f"written {written_ago} ago, within --idle-for {format_age(idle_for_seconds)}"
    )


def process_skip_reason(
    build_dir: BuildDir, list_processes: ProcessLister
) -> str | None:
    try:
        processes = list_processes()
    except ProcessListingError as error:
        return f"cannot check running processes: {error}"
    return build_dir.kind.in_use(build_dir.path, processes)


@contextlib.contextmanager
def holding_locks(build_dir: BuildDir) -> Generator[str | None]:
    """Hold an exclusive `flock` on every lock file of a build directory.

    Yields None while all locks are held, or a skip reason naming the first
    lock that is held elsewhere or cannot be opened. Lock files are never
    created, and every acquired lock is released on exit.
    """
    with contextlib.ExitStack() as held:
        for lock_path in build_dir.kind.lock_paths(build_dir.path):
            try:
                descriptor = os.open(
                    lock_path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC
                )
            except FileNotFoundError:
                continue
            except OSError as error:
                yield f"locked: cannot open {lock_path}: {error.strerror}"
                return
            _ = held.callback(os.close, descriptor)

            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                yield f"locked: {lock_path.relative_to(build_dir.path)} is held"
                return
        yield None


# Finding and measuring build directories


def find_build_dirs(
    roots: Sequence[Path], kinds: Sequence[SweepKind]
) -> list[BuildDir]:
    """Find directories under `roots` that a sweep kind matches.

    Symlinks are never followed. Neither a matched directory nor one a kind
    protects is searched for further matches. Unreadable directories are
    skipped with a note.
    """
    build_dirs: list[BuildDir] = []
    pending = list(roots)
    while len(pending) > 0:
        directory = pending.pop()
        kind = next((kind for kind in kinds if kind.matches(directory)), None)
        if kind is not None:
            build_dirs.append(BuildDir(path=directory, kind=kind))
            continue
        if any(kind.protects(directory) for kind in kinds):
            continue

        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    if entry.is_dir(follow_symlinks=False):
                        pending.append(Path(entry.path))
        except OSError as error:
            print(f"note: cannot read {directory}: {error.strerror}")
    return sorted(build_dirs, key=lambda build_dir: build_dir.path)


def measure_usage(directory: Path) -> BuildDirUsage:
    """Measure a build directory without following symlinks.

    Raises OSError when the directory itself cannot be inspected; unreadable
    entries inside it are left out of the totals.
    """
    root_stat = directory.lstat()
    allocated_bytes = root_stat.st_blocks * 512
    last_activity = root_stat.st_mtime
    counted_inodes: set[tuple[int, int]] = set()

    pending = [directory]
    while len(pending) > 0:
        current = pending.pop()
        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    entry_stat = entry.stat(follow_symlinks=False)
                    last_activity = max(last_activity, entry_stat.st_mtime)
                    if stat.S_ISDIR(entry_stat.st_mode):
                        pending.append(Path(entry.path))

                    inode = (entry_stat.st_dev, entry_stat.st_ino)
                    if entry_stat.st_nlink > 1 and not stat.S_ISDIR(entry_stat.st_mode):
                        if inode in counted_inodes:
                            continue
                        counted_inodes.add(inode)
                    allocated_bytes += entry_stat.st_blocks * 512
        except OSError:
            continue
    return BuildDirUsage(allocated_bytes=allocated_bytes, last_activity=last_activity)


# Sweep kinds


@dataclass(frozen=True)
class SweepKind:
    """One kind of regenerable build output that scratch-sweep can remove.

    `default_roots` lists directories scanned when no ROOT is given.
    `matches` recognizes a directory of this kind. `protects` recognizes a
    directory that is not of this kind but whose whole subtree must stay
    untouched, so the walk never descends into it. `lock_paths` lists the
    lock files to hold during removal; a lock held elsewhere means the
    directory is in use. `in_use` returns a skip reason, or None, given the
    running processes' paths.
    """

    name: str
    default_roots: Callable[[], list[Path]]
    matches: Callable[[Path], bool]
    protects: Callable[[Path], bool]
    lock_paths: Callable[[Path], list[Path]]
    in_use: Callable[[Path, Sequence[ProcessPath]], str | None]


def temporary_roots() -> list[Path]:
    """Temp roots where agents put build copies, whether or not they exist.

    These are the per-launch agent roots, Claude's own temp root, and the
    system user temp directory. On Darwin the latter comes from `getconf`,
    so a run inside an agent whose `TMPDIR` was relocated still scans it.
    """
    uid = os.getuid()
    roots = [Path(f"/tmp/agent-{uid}"), Path(f"/tmp/claude-{uid}")]
    if sys.platform == "darwin":
        try:
            output = subprocess.run(
                ["/usr/bin/getconf", "DARWIN_USER_TEMP_DIR"],
                capture_output=True,
                check=True,
                text=True,
            ).stdout.strip()
        except (OSError, subprocess.CalledProcessError):
            output = ""
        if output != "":
            roots.append(Path(output))
    else:
        roots.append(Path(os.environ.get("TMPDIR") or "/tmp"))
    return roots


# Running processes


@dataclass(frozen=True)
class ProcessPath:
    """A running process's executable or working directory, as a real path."""

    pid: int
    role: Literal["executable", "working directory"]
    path: str


ProcessLister = Callable[[], Sequence[ProcessPath]]


class ProcessListingError(Exception):
    pass


def process_inside(directory: Path, processes: Sequence[ProcessPath]) -> str | None:
    """A skip reason naming a process whose executable or cwd is inside `directory`."""
    for process in processes:
        if is_inside(process.path, str(directory)):
            return f"in use by pid {process.pid} ({process.role} inside)"
    return None


def list_process_paths() -> list[ProcessPath]:
    """List running processes' executables and working directories.

    Raises ProcessListingError when `ps` or `lsof` fails.
    """
    ps = "/bin/ps" if Path("/bin/ps").exists() else "ps"
    return [
        *parse_ps_executables(run_listing([ps, "-axo", "pid=,comm="])),
        *parse_lsof_paths(run_listing(["lsof", "-d", "cwd,txt", "-Fpfn"])),
    ]


def parse_ps_executables(output: str) -> list[ProcessPath]:
    """Executables from `ps -o pid=,comm=` output, resolved to real paths.

    macOS prints the path the process was executed with, so only absolute
    paths are kept; a relative one, such as `./target/debug/app`, is left to
    the `lsof` listing, which reports it in full.
    """
    paths: list[ProcessPath] = []
    for line in output.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and fields[0].isdigit() and fields[1].startswith("/"):
            paths.append(
                ProcessPath(
                    pid=int(fields[0]),
                    role="executable",
                    path=os.path.realpath(fields[1]),
                )
            )
    return paths


def parse_lsof_paths(output: str) -> list[ProcessPath]:
    """Working directories and program files from `lsof -d cwd,txt -Fpfn` output.

    A `txt` file is the process executable or a loaded library; both count as
    executables. Paths are resolved to real paths so they compare with
    resolved roots.
    """
    paths: list[ProcessPath] = []
    pid = 0
    role: Literal["executable", "working directory"] | None = None
    for line in output.splitlines():
        if line.startswith("p") and line[1:].isdigit():
            pid = int(line[1:])
            role = None
        elif line == "fcwd":
            role = "working directory"
        elif line == "ftxt":
            role = "executable"
        elif line.startswith("f"):
            role = None
        elif line.startswith("n/") and pid > 0 and role is not None:
            paths.append(
                ProcessPath(
                    pid=pid,
                    role=role,
                    path=os.path.realpath(line[1:]),
                )
            )
    return paths


def run_listing(arguments: list[str]) -> str:
    try:
        completed = subprocess.run(
            arguments,
            capture_output=True,
            check=False,
            errors="replace",
            text=True,
        )
    except OSError as error:
        raise ProcessListingError(f"could not run {arguments[0]}: {error}") from error
    if completed.returncode != 0 and completed.stdout == "":
        raise ProcessListingError(
            f"{arguments[0]} exited with status {completed.returncode}"
        )
    return completed.stdout


# Cargo kind


CACHEDIR_TAG_SIGNATURE = b"Signature: 8a477f597d28d172789f06886806bc55"
CARGO_LOCK_NAMES = frozenset(
    {".cargo-lock", ".cargo-build-lock", ".cargo-artifact-lock"}
)
CARGO_LOCK_MAX_DEPTH = 3


def is_cargo_build_dir(directory: Path) -> bool:
    """Whether `directory` is a Cargo target directory.

    It must hold Cargo's cache tag and a regular `.rustc_info.json`, which
    Cargo writes at the root of every target directory.
    """
    return has_cargo_cache_tag(directory) and is_regular_file(
        directory / ".rustc_info.json"
    )


def is_cargo_download_cache(directory: Path) -> bool:
    """Whether `directory` is a Cargo cache that is not a target directory.

    `$CARGO_HOME/registry` and `$CARGO_HOME/git` carry Cargo's cache tag but
    hold downloads that offline builds depend on, including published crate
    sources that may themselves ship a target directory.
    """
    return has_cargo_cache_tag(directory) and not is_cargo_build_dir(directory)


def has_cargo_cache_tag(directory: Path) -> bool:
    """Whether `directory` holds a regular `CACHEDIR.TAG` written by Cargo."""
    try:
        descriptor = os.open(
            directory / "CACHEDIR.TAG", os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC
        )
    except OSError:
        return False
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            return False
        content = os.read(descriptor, 4096)
    except OSError:
        return False
    finally:
        os.close(descriptor)
    return content.startswith(CACHEDIR_TAG_SIGNATURE) and b"created by cargo" in content


def is_regular_file(path: Path) -> bool:
    try:
        return stat.S_ISREG(path.lstat().st_mode)
    except OSError:
        return False


def cargo_lock_paths(directory: Path) -> list[Path]:
    """Cargo lock files within three levels of a build directory.

    That depth covers `debug/`, `release/`, and `<triple>/<profile>/`.
    """
    lock_paths: list[Path] = []
    pending = [(directory, 1)]
    while len(pending) > 0:
        current, depth = pending.pop()
        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    if entry.name in CARGO_LOCK_NAMES and entry.is_file(
                        follow_symlinks=False
                    ):
                        lock_paths.append(Path(entry.path))
                    elif depth < CARGO_LOCK_MAX_DEPTH and entry.is_dir(
                        follow_symlinks=False
                    ):
                        pending.append((Path(entry.path), depth + 1))
        except OSError:
            continue
    return sorted(lock_paths)


CARGO_KIND = SweepKind(
    name="cargo",
    default_roots=temporary_roots,
    matches=is_cargo_build_dir,
    protects=is_cargo_download_cache,
    lock_paths=cargo_lock_paths,
    in_use=process_inside,
)

SWEEP_KINDS: dict[str, SweepKind] = {kind.name: kind for kind in (CARGO_KIND,)}


# Formatting


def describe(build_dir: BuildDir, usage: BuildDirUsage, now: float) -> str:
    last_activity = datetime.fromtimestamp(usage.last_activity).strftime(
        "%Y-%m-%d %H:%M"
    )
    size = format_bytes(usage.allocated_bytes)
    age = format_age(now - usage.last_activity)
    return (
        f"{build_dir.path} ({build_dir.kind.name}, {size}, "
        + f"last activity {last_activity}, {age} ago)"
    )


def count_build_dirs(count: int) -> str:
    return f"{count} build directory" if count == 1 else f"{count} build directories"


def format_roots(roots: Sequence[Path]) -> str:
    if len(roots) == 0:
        return "(no existing roots)"
    return ", ".join(str(root) for root in roots)


def format_bytes(value: int) -> str:
    amount = float(value)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(amount) < 1024 or unit == "TiB":
            return f"{amount:.1f} {unit}" if unit != "B" else f"{int(amount)} B"
        amount /= 1024
    raise AssertionError("unreachable")


def format_age(seconds: float) -> str:
    """Format a duration as its two largest adjacent units, such as `3h 5m`."""
    remaining = max(0, int(seconds))
    units = ("d", "h", "m", "s")
    for index, unit in enumerate(units):
        count, rest = divmod(remaining, DURATION_UNIT_SECONDS[unit])
        if count == 0 and unit != "s":
            continue
        if index + 1 == len(units):
            return f"{count}{unit}"
        next_unit = units[index + 1]
        next_count = rest // DURATION_UNIT_SECONDS[next_unit]
        return (
            f"{count}{unit} {next_count}{next_unit}"
            if next_count > 0
            else f"{count}{unit}"
        )
    raise AssertionError("unreachable")


if __name__ == "__main__":
    raise SystemExit(main())
