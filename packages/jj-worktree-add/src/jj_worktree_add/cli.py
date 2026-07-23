"""Create conventionally located Git worktrees with independent jj state."""

from __future__ import annotations

import argparse
import os
import shlex
import stat
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from pathlib import Path
from typing import NoReturn, cast


MANAGED_ROOT = ".jj-worktrees"
IGNORE_RULE = b"*"


class WorktreeAddError(Exception):
    """A concise, user-facing creation failure."""


def _run(command: Sequence[str], *, cwd: Path | None = None) -> bytes:
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise WorktreeAddError(f"could not run {command[0]}: {error}") from error
    if result.returncode != 0:
        detail = os.fsdecode(result.stderr).strip()
        suffix = f": {detail}" if detail else ""
        raise WorktreeAddError(f"{' '.join(command)} failed{suffix}")
    return result.stdout


def _line(command: Sequence[str], *, cwd: Path | None = None) -> str:
    output = _run(command, cwd=cwd)
    if not output.endswith(b"\n") or b"\n" in output[:-1] or not output[:-1]:
        raise WorktreeAddError(f"{' '.join(command)} returned invalid output")
    return os.fsdecode(output[:-1])


def _validate_name(name: str) -> None:
    if (
        not name
        or name in {".", "..", ".gitignore"}
        or Path(name).name != name
        or any(ord(character) < 32 or ord(character) == 127 for character in name)
    ):
        raise WorktreeAddError("NAME must be one safe path component")


def _primary_worktree(start: Path) -> Path:
    output = _run(["git", "-C", os.fspath(start), "worktree", "list", "--porcelain", "-z"])
    first = output.split(b"\0\0", 1)[0]
    for field in first.split(b"\0"):
        key, separator, value = field.partition(b" ")
        if key == b"worktree" and separator:
            path = Path(os.fsdecode(value))
            if not path.is_absolute():
                break
            try:
                return path.resolve(strict=True)
            except OSError as error:
                raise WorktreeAddError(f"primary Git worktree is unavailable: {error}") from error
    raise WorktreeAddError("git returned malformed worktree metadata")


def _resolve_revision(start: Path, revision: str) -> str:
    return _line(
        [
            "jj",
            "--no-pager",
            "--color=never",
            "-R",
            os.fspath(start),
            "log",
            "--no-graph",
            "-r",
            f"exactly(({revision}), 1)",
            "-T",
            'commit_id ++ "\\n"',
        ]
    )


def _normalized_gitignore(original: bytes) -> bytes:
    lines = original.splitlines(keepends=True)
    if any(line.rstrip(b"\r\n") == IGNORE_RULE for line in lines):
        return original
    if lines and not lines[-1].endswith((b"\n", b"\r")):
        lines[-1] += b"\n"
    lines.append(IGNORE_RULE + b"\n")
    return b"".join(lines)


def _write_atomic(path: Path, content: bytes, mode: int) -> None:
    temporary: Path | None = None
    try:
        descriptor, name = tempfile.mkstemp(prefix=".gitignore.", dir=path.parent)
        temporary = Path(name)
        with os.fdopen(descriptor, "wb") as stream:
            _ = stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
        temporary = None
    except OSError as error:
        raise WorktreeAddError(f"could not update {path}: {error}") from error
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _ensure_managed_root(primary: Path) -> Path:
    root = primary / MANAGED_ROOT
    try:
        root.mkdir(exist_ok=True)
        if not stat.S_ISDIR(root.lstat().st_mode) or root.is_symlink():
            raise WorktreeAddError(f"{root} is not a directory")
        gitignore = root / ".gitignore"
        try:
            mode = gitignore.lstat().st_mode
        except FileNotFoundError:
            mode = 0o644
            original = b""
        else:
            if not stat.S_ISREG(mode) or stat.S_ISLNK(mode):
                raise WorktreeAddError(f"{gitignore} is not a regular file")
            original = gitignore.read_bytes()
        updated = _normalized_gitignore(original)
        if updated != original:
            _write_atomic(gitignore, updated, stat.S_IMODE(mode))
    except WorktreeAddError:
        raise
    except OSError as error:
        raise WorktreeAddError(f"could not initialize {root}: {error}") from error
    return root


def add(name: str, revision: str = "@", start: Path | None = None) -> Path:
    """Create and initialize one detached worktree, returning its absolute path."""
    _validate_name(name)
    current = (Path.cwd() if start is None else start).resolve(strict=True)
    primary = _primary_worktree(current)
    commit = _resolve_revision(current, revision)
    destination = _ensure_managed_root(primary) / name
    if destination.exists() or destination.is_symlink():
        raise WorktreeAddError(f"destination already exists: {destination}")
    _ = _run(
        ["git", "-C", os.fspath(primary), "worktree", "add", "--detach", os.fspath(destination), commit]
    )
    try:
        _ = _run(["jj-ensure", os.fspath(destination)])
    except WorktreeAddError as error:
        recovery = f"jj-ensure {shlex.quote(os.fspath(destination))}"
        message = (
            f"created Git worktree at {destination}, but jj initialization failed: {error}; "
            f"the worktree was preserved; recover with: {recovery}"
        )
        raise WorktreeAddError(message) from error
    return destination.resolve(strict=True)


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="jj-worktree-add",
        description=(
            "Create a detached Git worktree at the primary checkout's "
            ".jj-worktrees/NAME and initialize independent jj state."
        ),
        epilog=(
            "REVSET must resolve to exactly one commit and defaults to @. "
            "Use native git worktree commands for all later lifecycle operations."
        ),
    )
    _ = parser.add_argument("name", metavar="NAME")
    _ = parser.add_argument("-r", dest="revision", metavar="REVSET", default="@")
    return parser


def _exit_error(error: WorktreeAddError) -> NoReturn:
    print(f"error: {error}", file=sys.stderr)
    raise SystemExit(1)


def main(argv: list[str] | None = None) -> int:
    namespace = create_parser().parse_args(argv)
    try:
        print(add(cast(str, namespace.name), cast(str, namespace.revision)))
    except (OSError, WorktreeAddError) as error:
        _exit_error(WorktreeAddError(str(error)))
    return 0
