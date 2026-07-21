#!/usr/bin/env python3
# pyright: reportImplicitRelativeImport=false, reportPrivateUsage=false
# pyright: reportUninitializedInstanceVariable=false

from __future__ import annotations

import io
import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final, override
from unittest.mock import patch

from jj_worktree import cli
from jj_worktree.commands import attach, init, remove
from jj_worktree.commands import list as list_command
from jj_worktree.core import managed, process, repository

from support import run


class ExternalAttachmentFixture(unittest.TestCase):
    temporary_directory: TemporaryDirectory[str]
    root: Path
    primary: Path

    @override
    def setUp(self) -> None:
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name).resolve()
        self.primary = self.root / "primary"
        self.primary.mkdir()
        _ = run("git", "init", str(self.primary))
        _ = run("git", "-C", str(self.primary), "config", "user.name", "Test User")
        _ = run(
            "git", "-C", str(self.primary), "config", "user.email", "test@example.com"
        )
        _ = (self.primary / "tracked").write_text("initial\n")
        _ = run("git", "-C", str(self.primary), "add", "tracked")
        _ = run("git", "-C", str(self.primary), "commit", "-m", "initial")

    def create_external(self, name: str, *, detached: bool = True) -> Path:
        path = self.root / name
        arguments = [
            "git",
            "-C",
            str(self.primary),
            "worktree",
            "add",
        ]
        if detached:
            arguments.append("--detach")
        else:
            arguments.extend(["-b", f"test-{name}"])
        arguments.extend([str(path), "HEAD"])
        _ = run(*arguments)
        return path

    def git_state(self, path: Path) -> tuple[str, str, bytes, bytes | None, bytes]:
        private = Path(
            run("git", "-C", str(path), "rev-parse", "--absolute-git-dir").stdout.strip()
        )
        index = private / "index"
        return (
            run("git", "-C", str(path), "symbolic-ref", "-q", "HEAD", check=False).stdout,
            run(
                "git", "-C", str(self.primary), "for-each-ref", "refs/heads", "--format=%(objectname) %(refname)"
            ).stdout,
            (private / "HEAD").read_bytes(),
            index.read_bytes() if index.exists() else None,
            (path / "tracked").read_bytes(),
        )

    def operation_id(self, path: Path) -> str:
        return run(
            "jj", "-R", str(path), "op", "log", "--no-graph", "-n", "1", "-T", "id"
        ).stdout

    def worktree_paths(self) -> list[Path]:
        output = run(
            "git", "-C", str(self.primary), "worktree", "list", "--porcelain"
        ).stdout
        return [
            Path(line.removeprefix("worktree "))
            for line in output.splitlines()
            if line.startswith("worktree ")
        ]

    def checked_out_files(self, path: Path) -> dict[Path, bytes]:
        return {
            item.relative_to(path): item.read_bytes()
            for item in path.iterdir()
            if item.name not in {".git", ".jj"} and item.is_file()
        }


@final
class AttachBehaviorTests(ExternalAttachmentFixture):
    def test_attaches_external_worktree_without_primary_jj(self) -> None:
        external = self.create_external("external")
        output = io.StringIO()
        with patch("sys.stdout", output):
            self.assertEqual(cli.main(["attach", str(external)]), 0)
        private = Path(
            run(
                "git", "-C", str(external), "rev-parse", "--absolute-git-dir"
            ).stdout.strip()
        )
        self.assertEqual(output.getvalue(), f"{external}\n")
        self.assertEqual(Path(run("jj", "-R", str(external), "root").stdout.strip()), external)
        self.assertEqual(
            Path(run("jj", "-R", str(external), "git", "root").stdout.strip()), private
        )
        self.assertFalse((self.primary / ".jj").exists())

    def test_preserves_git_worktree_state(self) -> None:
        externals = [
            (self.create_external("attached", detached=False), False),
            (self.create_external("detached"), True),
        ]
        for external, detached in externals:
            with self.subTest(detached=detached):
                private = Path(
                    run(
                        "git", "-C", str(external), "rev-parse", "--absolute-git-dir"
                    ).stdout.strip()
                )
                files = self.checked_out_files(external)
                self.assertEqual(
                    bool(
                        run(
                            "git",
                            "-C",
                            str(external),
                            "symbolic-ref",
                            "-q",
                            "HEAD",
                            check=False,
                        ).stdout
                    ),
                    not detached,
                )
                self.assertEqual(attach.attach_worktree(external), external)
                self.assertEqual(self.worktree_paths().count(external), 1)
                self.assertTrue(
                    os.path.samefile(
                        private,
                        run(
                            "git", "-C", str(external), "rev-parse", "--absolute-git-dir"
                        ).stdout.strip(),
                    )
                )
                self.assertEqual(self.checked_out_files(external), files)

    def test_attaches_dirty_worktree(self) -> None:
        _ = run("jj", "git", "init", "--colocate", str(self.primary))
        primary_operation = self.operation_id(self.primary)
        external = self.create_external("dirty")
        _ = (external / "tracked").write_text("changed\n")
        _ = (external / "untracked").write_bytes(b"untracked\n")
        contents = ((external / "tracked").read_bytes(), (external / "untracked").read_bytes())
        self.assertEqual(attach.attach_worktree(external), external)
        self.assertEqual(
            ((external / "tracked").read_bytes(), (external / "untracked").read_bytes()),
            contents,
        )
        jj_status = run("jj", "-R", str(external), "status").stdout
        self.assertIn("tracked", jj_status)
        self.assertIn("untracked", jj_status)
        self.assertEqual(self.operation_id(self.primary), primary_operation)


@final
class AttachSafetyTests(ExternalAttachmentFixture):
    def test_compatible_attachment_is_idempotent(self) -> None:
        external = self.create_external("external")
        first = attach.attach_worktree(external)
        private = run(
            "jj", "-R", str(external), "git", "root"
        ).stdout
        operation = self.operation_id(external)
        git_state = self.git_state(external)
        jj_state = os.stat(external / ".jj")
        second = attach.attach_worktree(external)
        self.assertEqual((first, second), (external, external))
        self.assertEqual(run("jj", "-R", str(external), "git", "root").stdout, private)
        self.assertEqual(self.operation_id(external), operation)
        self.assertEqual(self.git_state(external), git_state)
        self.assertTrue(os.path.samestat(os.stat(external / ".jj"), jj_state))

    def test_rejects_invalid_targets(self) -> None:
        plain = self.root / "plain"
        plain.mkdir()
        marker = plain / "marker"
        _ = marker.write_bytes(b"safe")
        with self.assertRaises(process.WorktreeError):
            _ = attach.attach_worktree(plain)
        self.assertEqual(marker.read_bytes(), b"safe")
        with self.assertRaisesRegex(process.WorktreeError, "primary"):
            _ = attach.attach_worktree(self.primary)

        external = self.create_external("incompatible")
        incompatible = external / ".jj"
        incompatible.mkdir()
        _ = (incompatible / "keep").write_bytes(b"keep")
        registrations = run(
            "git", "-C", str(self.primary), "worktree", "list", "--porcelain", "-z"
        ).stdout
        with self.assertRaises(process.WorktreeError):
            _ = attach.attach_worktree(external)
        self.assertEqual((incompatible / "keep").read_bytes(), b"keep")
        self.assertEqual(
            run(
                "git", "-C", str(self.primary), "worktree", "list", "--porcelain", "-z"
            ).stdout,
            registrations,
        )

        for name, target_record, expected in (
            ("unregistered", None, "not uniquely registered"),
            ("stale", b"prunable stale metadata\0", "stale"),
        ):
            with self.subTest(name=name):
                invalid = self.create_external(name)
                records = repository.parse_worktrees(invalid)
                if target_record is None:
                    records = records[:1]
                else:
                    records = [
                        repository.GitWorktree(
                            record.path, None, record.head, record.detached
                        )
                        if record.path == invalid
                        else record
                        for record in records
                    ]

                with patch.object(
                    repository,
                    "parse_worktrees",
                    return_value=records,
                ):
                    with self.assertRaisesRegex(process.WorktreeError, expected):
                        _ = attach.attach_worktree(invalid)
                self.assertFalse((invalid / ".jj").exists())

    def test_failure_preserves_external_ownership(self) -> None:
        initialization = self.create_external("initialization")
        validation = self.create_external("validation")
        targets = (initialization, validation)
        for target in targets:
            _ = (target / "keep").write_bytes(b"keep")
        registrations = self.worktree_paths()
        real_checked = process.checked
        real_run = process.run

        def fail_initialization(
            command: list[str] | tuple[str, ...],
            *,
            cwd: Path | None = None,
            label: str | None = None,
        ) -> bytes:
            if label == "jj external-worktree initialization":
                (initialization / ".jj").mkdir()
                _ = (initialization / ".jj" / "partial").write_bytes(b"partial")
                raise process.WorktreeError("simulated initialization failure")
            return real_checked(command, cwd=cwd, label=label)

        def reject_worktree_removal(
            command: list[str] | tuple[str, ...],
            *,
            cwd: Path | None = None,
            input_data: bytes | None = None,
        ) -> subprocess.CompletedProcess[bytes]:
            if "git" in command and "worktree" in command and "remove" in command:
                self.fail("attach attempted to remove an external Git worktree")
            return real_run(command, cwd=cwd, input_data=input_data)

        with patch.object(process, "run", side_effect=reject_worktree_removal):
            with patch.object(process, "checked", side_effect=fail_initialization):
                with self.assertRaisesRegex(process.WorktreeError, "initialization failure"):
                    _ = attach.attach_worktree(initialization)

            with patch.object(
                managed,
                "validate_attached_jj",
                side_effect=process.WorktreeError("validation failed"),
            ):
                with self.assertRaisesRegex(process.WorktreeError, "validation failed"):
                    _ = attach.attach_worktree(validation)

        self.assertEqual(self.worktree_paths(), registrations)
        for target in targets:
            self.assertTrue(target.is_dir())
            self.assertEqual((target / "keep").read_bytes(), b"keep")
            self.assertFalse((target / ".jj").exists())

    def test_rejects_external_worktrees_inside_managed_namespace(self) -> None:
        _ = run("jj", "git", "init", "--colocate", str(self.primary))
        _ = init.initialize(self.primary)
        managed = self.primary / repository.MANAGED_ROOT_NAME
        managed.mkdir(exist_ok=True)
        direct = managed / "external"
        nested_parent = managed / "nested"
        nested_parent.mkdir()
        nested = nested_parent / "external"
        for target in (direct, nested):
            _ = run(
                "git",
                "-C",
                str(self.primary),
                "worktree",
                "add",
                "--detach",
                str(target),
                "HEAD",
            )
            with self.assertRaisesRegex(process.WorktreeError, "managed namespace"):
                _ = attach.attach_worktree(target)
            self.assertFalse((target / ".jj").exists())

        direct_record = list_command.list_worktrees(["external"], self.primary)[0]
        self.assertNotEqual(direct_record.status, "ok")
        with self.assertRaises(process.WorktreeError):
            remove.remove_worktree("external", confirm=True, start=self.primary)
        self.assertTrue(direct.is_dir())
        self.assertEqual(
            list_command.list_worktrees(["nested"], self.primary)[0].status,
            "missing",
        )


@final
class AttachCliTests(unittest.TestCase):
    def test_dispatches_default_and_explicit_paths_and_reports_errors(self) -> None:
        output = io.StringIO()
        with (
            patch.object(attach, "attach_worktree", return_value=Path("/canonical")) as attach_mock,
            patch("sys.stdout", output),
        ):
            self.assertEqual(cli.main(["attach"]), 0)
        attach_mock.assert_called_once_with(Path("."))
        self.assertEqual(output.getvalue(), "/canonical\n")

        with (
            patch.object(attach, "attach_worktree", return_value=Path("/explicit")) as attach_mock,
            patch("sys.stdout", io.StringIO()),
        ):
            self.assertEqual(cli.main(["attach", "target"]), 0)
        attach_mock.assert_called_once_with(Path("target"))

        error = io.StringIO()
        with (
            patch.object(
                attach,
                "attach_worktree",
                side_effect=process.WorktreeError("invalid target"),
            ),
            patch("sys.stderr", error),
        ):
            self.assertEqual(cli.main(["attach"]), 1)
        self.assertIn("error: invalid target", error.getvalue())

    def test_help_documents_external_ownership_and_compatibility_warning(self) -> None:
        output = io.StringIO()
        with patch("sys.stdout", output):
            with self.assertRaises(SystemExit) as exit_status:
                _ = cli.create_parser().parse_args(["attach", "--help"])
        self.assertEqual(exit_status.exception.code, 0)
        help_text = output.getvalue()
        for expected in (
            "externally owned",
            "never manages its lifecycle",
            "Attachment and later mutating jj commands",
            "detach its Git",
            "rewrite its Git index",
            "unsupported jj compatibility dependency",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, help_text)



if __name__ == "__main__":
    _ = unittest.main()
