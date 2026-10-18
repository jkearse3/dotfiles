#!/usr/bin/env python3

from __future__ import annotations

import contextlib
import io
import os
import shutil
import subprocess
import sys
import time
import unittest
from collections.abc import Sequence
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final, override
from unittest.mock import patch

import scratch_sweep
from scratch_sweep import ProcessPath


CARGO_TAG = (
    "Signature: 8a477f597d28d172789f06886806bc55\n"
    + "# This file is a cache directory tag created by cargo.\n"
    + "# For information about cache directory tags see https://bford.info/cachedir/\n"
)
OTHER_TAG = (
    "Signature: 8a477f597d28d172789f06886806bc55\n"
    + "# This file is a cache directory tag created by some other tool.\n"
)


def no_processes() -> list[ProcessPath]:
    return []


def make_cargo_target(directory: Path) -> Path:
    """Create a minimal Cargo target directory with its tag, rustc info, and locks."""
    debug = directory / "debug"
    (debug / "deps").mkdir(parents=True)
    _ = (directory / "CACHEDIR.TAG").write_text(CARGO_TAG)
    _ = (directory / ".rustc_info.json").write_text('{"rustc_fingerprint":1}\n')
    for name in (".cargo-lock", ".cargo-build-lock", ".cargo-artifact-lock"):
        (debug / name).touch()
    _ = (debug / "deps" / "libexample.rlib").write_bytes(b"x" * 20000)
    return directory


def snapshot_tree(root: Path) -> dict[str, tuple[int, float]]:
    entries: dict[str, tuple[int, float]] = {}
    for directory, directory_names, file_names in os.walk(root):
        for name in [*directory_names, *file_names]:
            entry_stat = os.lstat(Path(directory) / name)
            entries[str(Path(directory, name).relative_to(root))] = (
                entry_stat.st_size,
                entry_stat.st_mtime,
            )
    return entries


def set_tree_mtime(root: Path, timestamp: float) -> None:
    for directory, directory_names, file_names in os.walk(root):
        for name in [*directory_names, *file_names]:
            os.utime(
                Path(directory) / name, (timestamp, timestamp), follow_symlinks=False
            )
    os.utime(root, (timestamp, timestamp))


def run_main(
    arguments: list[str],
    list_processes: scratch_sweep.ProcessLister = no_processes,
) -> tuple[int, str, str]:
    output = io.StringIO()
    errors = io.StringIO()
    with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
        try:
            status = scratch_sweep.main(arguments, list_processes=list_processes)
        except SystemExit as exit_request:
            status = exit_request.code if isinstance(exit_request.code, int) else 1
    return status, output.getvalue(), errors.getvalue()


@final
class ScratchSweepTest(unittest.TestCase):
    temporary_directory: TemporaryDirectory[str]
    root: Path
    copy: Path
    target: Path

    @override
    def setUp(self) -> None:
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name).resolve()
        self.copy = self.root / "copy"
        (self.copy / "src").mkdir(parents=True)
        _ = (self.copy / "src" / "main.rs").write_text("fn main() {}\n")
        _ = (self.root / "notes.txt").write_text("scratch notes\n")
        self.target = make_cargo_target(self.copy / "target")

    def test_matches_only_regular_cargo_cache_tags(self) -> None:
        other = self.root / "other-cache"
        other.mkdir()
        _ = (other / "CACHEDIR.TAG").write_text(OTHER_TAG)

        unsigned = self.root / "unsigned"
        unsigned.mkdir()
        _ = (unsigned / "CACHEDIR.TAG").write_text("# created by cargo\n")

        linked_tag = self.root / "linked-tag"
        linked_tag.mkdir()
        (linked_tag / "CACHEDIR.TAG").symlink_to(self.target / "CACHEDIR.TAG")

        directory_tag = self.root / "directory-tag"
        (directory_tag / "CACHEDIR.TAG").mkdir(parents=True)

        for directory in (other, unsigned, linked_tag, directory_tag):
            (directory / ".rustc_info.json").touch()

        found = scratch_sweep.find_build_dirs([self.root], [scratch_sweep.CARGO_KIND])
        self.assertEqual([build_dir.path for build_dir in found], [self.target])

    def test_cargo_home_caches_do_not_match(self) -> None:
        registry = self.root / "cargo-home" / "registry"
        for name in ("cache", "index", "src"):
            (registry / name).mkdir(parents=True)
        _ = (registry / "CACHEDIR.TAG").write_text(CARGO_TAG)

        linked_info = self.root / "linked-info"
        linked_info.mkdir()
        _ = (linked_info / "CACHEDIR.TAG").write_text(CARGO_TAG)
        (linked_info / ".rustc_info.json").symlink_to(self.target / ".rustc_info.json")

        found = scratch_sweep.find_build_dirs([self.root], [scratch_sweep.CARGO_KIND])
        self.assertEqual([build_dir.path for build_dir in found], [self.target])

    def test_target_vendored_in_cargo_home_cache_is_not_found(self) -> None:
        registry = self.root / "cargo-home" / "registry"
        crate = registry / "src" / "index.crates.io-0123" / "example-0.1.0"
        crate.mkdir(parents=True)
        _ = (registry / "CACHEDIR.TAG").write_text(CARGO_TAG)
        _ = make_cargo_target(crate / "docs")

        found = scratch_sweep.find_build_dirs([self.root], [scratch_sweep.CARGO_KIND])
        self.assertEqual([build_dir.path for build_dir in found], [self.target])

    def test_walk_does_not_follow_symlinks_or_descend_into_matches(self) -> None:
        (self.root / "link-to-copy").symlink_to(self.copy, target_is_directory=True)
        _ = make_cargo_target(self.target / "debug" / "nested-target")

        found = scratch_sweep.find_build_dirs([self.root], [scratch_sweep.CARGO_KIND])
        self.assertEqual([build_dir.path for build_dir in found], [self.target])

    def test_report_lists_build_dirs_without_changing_the_tree(self) -> None:
        before = snapshot_tree(self.root)

        status, output, _ = run_main(["report", str(self.root)])

        self.assertEqual(status, 0)
        self.assertEqual(snapshot_tree(self.root), before)
        self.assertIn(f"would remove {self.target} (cargo, ", output)
        self.assertIn("last activity ", output)
        self.assertIn("1 build directory", output)

    def test_lock_held_by_another_process_skips_the_directory(self) -> None:
        lock_path = self.target / "debug" / ".cargo-build-lock"
        holder: subprocess.Popen[str] = subprocess.Popen(
            [
                sys.executable,
                "-c",
                "import fcntl, sys\n"
                + "lock = open(sys.argv[1])\n"
                + "fcntl.flock(lock, fcntl.LOCK_EX)\n"
                + "print('held', flush=True)\n"
                + "sys.stdin.read()\n",
                str(lock_path),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        )
        holder_input, holder_output = holder.stdin, holder.stdout
        assert holder_input is not None and holder_output is not None
        self.addCleanup(holder.wait)
        self.addCleanup(holder_input.close)
        self.addCleanup(holder_output.close)
        ready_line: str = holder_output.readline()
        self.assertEqual(ready_line.strip(), "held")

        report_status, report_output, _ = run_main(["report", str(self.root)])
        clean_status, clean_output, _ = run_main(["clean", str(self.root)])

        self.assertEqual(report_status, 0)
        self.assertIn("locked: debug/.cargo-build-lock is held", report_output)
        self.assertEqual(clean_status, 0)
        self.assertIn("locked: debug/.cargo-build-lock is held", clean_output)
        self.assertTrue(self.target.is_dir())

    def test_lock_paths_cover_profile_and_target_triple_directories(self) -> None:
        triple_profile = self.target / "aarch64-apple-darwin" / "release"
        triple_profile.mkdir(parents=True)
        (triple_profile / ".cargo-lock").touch()
        too_deep = self.target / "debug" / "build" / "example-1234"
        too_deep.mkdir(parents=True)
        (too_deep / ".cargo-lock").touch()

        self.assertEqual(
            scratch_sweep.cargo_lock_paths(self.target),
            sorted(
                [
                    triple_profile / ".cargo-lock",
                    self.target / "debug" / ".cargo-artifact-lock",
                    self.target / "debug" / ".cargo-build-lock",
                    self.target / "debug" / ".cargo-lock",
                ]
            ),
        )

    def test_running_process_inside_skips_the_directory(self) -> None:
        test_binary = str(self.target / "debug" / "deps" / "example-0123abcd")
        cases = (
            (ProcessPath(pid=4242, role="executable", path=test_binary), "pid 4242"),
            (
                ProcessPath(pid=4343, role="working directory", path=str(self.target)),
                "pid 4343",
            ),
        )
        for process, expected in cases:
            with self.subTest(role=process.role):

                def list_processes(process: ProcessPath = process) -> list[ProcessPath]:
                    return [process]

                status, output, _ = run_main(["clean", str(self.root)], list_processes)
                self.assertEqual(status, 0)
                self.assertIn(expected, output)
                self.assertTrue(self.target.is_dir())

    def test_process_listing_parses_ps_and_lsof_output(self) -> None:
        binary = str(self.target / "debug" / "app")
        ps_output = f"  101 {binary}\n  102 ./target/debug/app\n  103 -fish\n"
        lsof_output = (
            f"p102\nfcwd\nn{self.root}\nftxt\nn{binary}\nftxt\nn/usr/lib/dyld\n"
            + f"p104\nfcwd\nn{self.target}\nf3\nn{self.target}/ignored\n"
        )

        self.assertEqual(
            scratch_sweep.parse_ps_executables(ps_output),
            [ProcessPath(pid=101, role="executable", path=binary)],
        )
        self.assertEqual(
            scratch_sweep.parse_lsof_paths(lsof_output),
            [
                ProcessPath(pid=102, role="working directory", path=str(self.root)),
                ProcessPath(pid=102, role="executable", path=binary),
                ProcessPath(pid=102, role="executable", path="/usr/lib/dyld"),
                ProcessPath(pid=104, role="working directory", path=str(self.target)),
            ],
        )

    def test_process_in_sibling_with_shared_prefix_does_not_skip(self) -> None:
        def list_processes() -> list[ProcessPath]:
            return [
                ProcessPath(pid=1, role="working directory", path=f"{self.target}2")
            ]

        status, _, _ = run_main(["clean", str(self.root)], list_processes)

        self.assertEqual(status, 0)
        self.assertFalse(self.target.exists())

    def test_failed_process_listing_skips_the_directory(self) -> None:
        def list_processes() -> Sequence[ProcessPath]:
            raise scratch_sweep.ProcessListingError("lsof exited with status 1")

        status, output, _ = run_main(["clean", str(self.root)], list_processes)

        self.assertEqual(status, 0)
        self.assertIn("cannot check running processes", output)
        self.assertTrue(self.target.is_dir())

    def test_idle_for_skips_recent_writes(self) -> None:
        now = time.time()
        set_tree_mtime(self.target, now - 3 * 3600)
        recent = self.target / "debug" / "deps" / "libexample.rlib"
        os.utime(recent, (now - 3600, now - 3600))

        status, output, _ = run_main(["clean", "--idle-for", "2h", str(self.root)])
        self.assertEqual(status, 0)
        self.assertIn("within --idle-for 2h", output)
        self.assertTrue(self.target.is_dir())

        os.utime(recent, (now - 3 * 3600, now - 3 * 3600))
        status, output, _ = run_main(["clean", "--idle-for", "2h", str(self.root)])
        self.assertEqual(status, 0)
        self.assertFalse(self.target.exists())

    def test_idle_for_zero_removes_fresh_output(self) -> None:
        status, _, _ = run_main(["clean", "--idle-for", "0", str(self.root)])

        self.assertEqual(status, 0)
        self.assertFalse(self.target.exists())

    def test_clean_removes_only_build_dirs_and_reports_freed_bytes(self) -> None:
        usage = scratch_sweep.measure_usage(self.target)

        status, output, _ = run_main(["clean", str(self.root)])

        self.assertEqual(status, 0)
        self.assertFalse(self.target.exists())
        self.assertTrue((self.copy / "src" / "main.rs").is_file())
        self.assertTrue((self.root / "notes.txt").is_file())
        self.assertEqual(
            sorted(path.name for path in self.copy.iterdir()),
            ["src"],
        )
        self.assertGreater(usage.allocated_bytes, 0)
        freed = scratch_sweep.format_bytes(usage.allocated_bytes)
        self.assertIn(f"Freed {freed} from 1 build directory", output)

    def test_failed_deletion_exits_one_and_names_the_leftover(self) -> None:
        def fail_rmtree(path: str | os.PathLike[str]) -> None:
            raise PermissionError(13, "Permission denied", str(path))

        with patch.object(shutil, "rmtree", side_effect=fail_rmtree):
            status, _, errors = run_main(["clean", str(self.root)])

        self.assertEqual(status, 1)
        self.assertIn("error: could not remove", errors)
        self.assertIn(".scratch-sweep-", errors)
        self.assertFalse(self.target.exists())

    def test_hard_links_are_counted_once(self) -> None:
        before = scratch_sweep.measure_usage(self.target).allocated_bytes
        rlib = self.target / "debug" / "deps" / "libexample.rlib"
        os.link(rlib, self.target / "debug" / "example-linked.rlib")

        self.assertEqual(
            scratch_sweep.measure_usage(self.target).allocated_bytes, before
        )

    def test_idle_duration_syntax(self) -> None:
        self.assertEqual(scratch_sweep.idle_duration_seconds("0"), 0)
        self.assertEqual(scratch_sweep.idle_duration_seconds("45s"), 45)
        self.assertEqual(scratch_sweep.idle_duration_seconds("2h"), 7200)
        self.assertEqual(scratch_sweep.idle_duration_seconds("3d"), 259200)
        for invalid in ("", "2", "2H", "-1h", "1.5h", "2hours", "h"):
            with self.subTest(invalid=invalid):
                status, _, errors = run_main(
                    ["report", "--idle-for", invalid, str(self.root)]
                )
                self.assertEqual(status, 2)
                self.assertIn("--idle-for", errors)

    def test_usage_errors_exit_two(self) -> None:
        usage_errors: list[list[str]] = [
            [],
            ["sweep"],
            ["report", "--kind", "npm", str(self.root)],
            ["clean", str(self.root / "missing")],
        ]
        for arguments in usage_errors:
            with self.subTest(arguments=arguments):
                status, _, _ = run_main(arguments)
                self.assertEqual(status, 2)
        self.assertTrue(self.target.is_dir())

    def test_default_roots_skip_missing_and_nested_roots(self) -> None:
        roots = scratch_sweep.scan_roots(
            [self.root / "missing", self.copy, self.root, self.root / "notes.txt"]
        )

        self.assertEqual(roots, [self.root])

    def test_format_age_uses_adjacent_units(self) -> None:
        self.assertEqual(scratch_sweep.format_age(0), "0s")
        self.assertEqual(scratch_sweep.format_age(3 * 3600 + 5), "3h")
        self.assertEqual(scratch_sweep.format_age(3 * 3600 + 5 * 60), "3h 5m")
        self.assertEqual(scratch_sweep.format_age(-10), "0s")


if __name__ == "__main__":
    _ = unittest.main(argv=[sys.argv[0]])
