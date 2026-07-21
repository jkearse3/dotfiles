#!/usr/bin/env python3
# pyright: reportImplicitRelativeImport=false, reportPrivateUsage=false
# pyright: reportUninitializedInstanceVariable=false

from __future__ import annotations

import fcntl
import io
import os
import shutil
import subprocess
import unittest
from pathlib import Path
from typing import final, override
from unittest.mock import patch

from jj_worktree import cli
from jj_worktree.commands import add, init, remove
from jj_worktree.commands import list as list_command
from jj_worktree.commands import path as path_command
from jj_worktree.core import exclude, managed, process, repository

from support import RepositoryFixture, run


@final
class InspectionCliTests(unittest.TestCase):
    def test_path_prints_the_resolved_worktree(self) -> None:
        output = io.StringIO()
        with (
            patch.object(path_command, "worktree_path", return_value=Path("/resolved")) as resolve,
            patch("sys.stdout", output),
        ):
            self.assertEqual(cli.main(["path", "feature"]), 0)
        resolve.assert_called_once_with("feature")
        self.assertEqual(output.getvalue(), "/resolved\n")

    def test_list_prints_records_and_reports_invalid_status(self) -> None:
        records = [
            managed.WorktreeRecord("valid", Path("/valid"), "ok"),
            managed.WorktreeRecord("missing", None, "missing"),
        ]
        output = io.StringIO()
        with (
            patch.object(list_command, "list_worktrees", return_value=records) as listing,
            patch("sys.stdout", output),
        ):
            self.assertEqual(cli.main(["list", "valid", "missing"]), 1)
        listing.assert_called_once_with(["valid", "missing"])
        self.assertEqual(output.getvalue(), "valid\t/valid\tok\nmissing\t-\tmissing\n")


@final
class GitRepositoryDiscoveryTests(RepositoryFixture):
    def test_discovers_primary_and_private_git_directories(self) -> None:
        linked = self.create_linked("feature")
        primary = repository.discover_repository(self.primary)
        (linked / "subdir").mkdir()
        secondary = repository.discover_repository(linked / "subdir")
        self.assertEqual(primary.primary, self.primary)
        self.assertEqual(secondary.primary, self.primary)
        self.assertEqual(primary.current_git, self.primary / ".git")
        self.assertEqual(secondary.current, linked)
        self.assertEqual(secondary.common_git, self.primary / ".git")
        self.assertEqual(secondary.current_git.parent.parent, self.primary / ".git")

    def test_rejects_non_jj_and_foreign_linked_worktrees(self) -> None:
        plain = self.root / "plain"
        _ = run("git", "init", str(plain))
        with self.assertRaises(process.WorktreeError):
            _ = repository.discover_repository(plain)
        foreign = self.root / "foreign"
        _ = run("git", "-C", str(self.primary), "worktree", "add", "--detach", str(foreign), "HEAD")
        private = run("git", "-C", str(foreign), "rev-parse", "--absolute-git-dir").stdout.strip()
        _ = run("jj", "git", "init", f"--git-repo={private}", str(foreign))
        with self.assertRaisesRegex(process.WorktreeError, "outside the managed root"):
            _ = repository.discover_repository(foreign)


@final
class IgnoreInitializationTests(RepositoryFixture):
    def test_preserves_content_and_is_idempotent(self) -> None:
        _ = self.exclude().write_bytes(b"# retained\n/private\n/.jj-worktrees/\n")
        self.managed_root.mkdir()
        gitignore = self.managed_root / ".gitignore"
        _ = gitignore.write_bytes(b"# retained\n*\n")
        _ = init.initialize(self.primary)
        first = self.exclude().read_bytes()
        first_gitignore = gitignore.read_bytes()
        _ = init.initialize(self.primary)
        self.assertEqual(self.exclude().read_bytes(), first)
        self.assertEqual(gitignore.read_bytes(), first_gitignore)
        self.assertEqual(first, b"# retained\n/private\n/.jj-worktrees/\n")
        self.assertEqual(first_gitignore, b"# retained\n*\n")

    def test_initializes_from_linked_worktree_and_repairs_missing_file(self) -> None:
        linked = self.create_linked("feature")
        self.exclude().unlink()
        result = init.initialize(linked)
        self.assertEqual(result, self.primary)
        self.assertEqual(self.exclude().read_bytes(), b"/.jj-worktrees/\n")
        self.assertEqual((self.managed_root / ".gitignore").read_bytes(), b"*\n")
        ignored = run(
            "git",
            "-C",
            str(self.primary),
            "check-ignore",
            "--quiet",
            "--no-index",
            ".jj-worktrees/example",
            check=False,
        )
        self.assertEqual(ignored.returncode, 0)
        self.assertEqual(
            run(
                "jj",
                "-R",
                str(self.primary),
                "file",
                "list",
                f'root:"{repository.MANAGED_ROOT_NAME}"',
            ).stdout,
            "",
        )

    def test_verification_does_not_integrate_unrelated_snapshot(self) -> None:
        operation = run(
            "jj", "-R", str(self.primary), "op", "log", "--no-graph", "-n", "1", "-T", "id"
        ).stdout
        _ = (self.primary / "unrelated").write_text("dirty\n")
        _ = init.initialize(self.primary)
        self.assertEqual(
            run(
                "jj",
                "--ignore-working-copy",
                "-R",
                str(self.primary),
                "op",
                "log",
                "--no-graph",
                "-n",
                "1",
                "-T",
                "id",
            ).stdout,
            operation,
        )
        self.assertNotIn(
            "unrelated",
            run(
                "jj", "--ignore-working-copy", "-R", str(self.primary), "file", "list", "-r", "@"
            ).stdout.splitlines(),
        )


@final
class InitializationErrorTests(RepositoryFixture):
    def test_rejects_invalid_repositories_without_exclude_changes(self) -> None:
        before = self.exclude().read_bytes()
        outside = self.root / "outside"
        outside.mkdir()
        with self.assertRaises(process.WorktreeError):
            _ = init.initialize(outside)
        self.assertEqual(self.exclude().read_bytes(), before)

    def test_rejects_symlinked_exclude_and_locked_initialization(self) -> None:
        target = self.root / "target"
        _ = target.write_bytes(b"safe\n")
        self.exclude().unlink()
        self.exclude().symlink_to(target)
        with self.assertRaises(process.WorktreeError):
            _ = init.initialize(self.primary)
        self.assertEqual(target.read_bytes(), b"safe\n")
        self.exclude().unlink()
        _ = self.exclude().write_bytes(b"")
        lock = self.primary / ".git" / "info" / exclude.EXCLUDE_LOCK_NAME
        with lock.open("w") as lock_file:
            fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(process.WorktreeError, "another initialization"):
                _ = init.initialize(self.primary)

    def test_restores_exclude_when_ignore_verification_fails(self) -> None:
        before = self.exclude().read_bytes()
        with patch.object(exclude, "is_ignored", return_value=False):
            with self.assertRaises(process.WorktreeError):
                _ = init.initialize(self.primary)
        self.assertEqual(self.exclude().read_bytes(), before)
        self.assertFalse(self.managed_root.exists())

    def test_restores_existing_rules_when_jj_verification_fails(self) -> None:
        before_exclude = b"# existing\n"
        before_gitignore = b"# existing\n"
        _ = self.exclude().write_bytes(before_exclude)
        self.managed_root.mkdir()
        gitignore = self.managed_root / ".gitignore"
        _ = gitignore.write_bytes(before_gitignore)
        with patch.object(
            exclude,
            "is_jj_ignored",
            side_effect=process.WorktreeError("verification failed"),
        ):
            with self.assertRaisesRegex(process.WorktreeError, "verification failed"):
                _ = init.initialize(self.primary)
        self.assertEqual(self.exclude().read_bytes(), before_exclude)
        self.assertEqual(gitignore.read_bytes(), before_gitignore)

class CreatedFixture(RepositoryFixture):
    @override
    def setUp(self) -> None:
        super().setUp()
        self.create_bookmark("feature")

    def commit(self, repository: Path, revision: str) -> str:
        return run(
            "jj",
            "-R",
            str(repository),
            "log",
            "--no-graph",
            "-r",
            revision,
            "-T",
            "commit_id",
        ).stdout


@final
class AddTests(CreatedFixture):
    def test_add_uses_exact_bookmark_and_detached_git_worktree(self) -> None:
        created = add.add_worktree("feature", start=self.primary)
        self.assertEqual(created, self.managed_root / "feature")
        self.assertEqual(self.commit(created, "@-"), self.commit(self.primary, "feature"))
        branch = run(
            "git", "-C", str(created), "symbolic-ref", "-q", "HEAD", check=False
        )
        self.assertNotEqual(branch.returncode, 0)
        self.assertIn(exclude.MANAGED_IGNORE_RULE, self.exclude().read_bytes().splitlines())

    def test_add_accepts_one_explicit_revision(self) -> None:
        created = add.add_worktree("explicit", "@-", self.primary)
        self.assertEqual(self.commit(created, "@-"), self.commit(self.primary, "@-"))


    def test_add_from_linked_worktree_uses_primary_managed_root(self) -> None:
        first = add.add_worktree("feature", start=self.primary)
        _ = run("jj", "-R", str(first), "bookmark", "create", "second", "-r", "@-")
        created = add.add_worktree("second", start=first)
        self.assertEqual(created, self.managed_root / "second")
        self.assertFalse((first / repository.MANAGED_ROOT_NAME).exists())


@final
class InspectionTests(CreatedFixture):
    def test_path_and_list_use_git_records(self) -> None:
        created = add.add_worktree("feature", start=self.primary)
        self.assertEqual(path_command.worktree_path("feature", self.primary), created)
        self.assertEqual(
            list_command.list_worktrees(start=created),
            [managed.WorktreeRecord("feature", created, "ok")],
        )

    def test_reports_missing_unignored_and_malformed_records(self) -> None:
        self.assertEqual(
            list_command.list_worktrees(["missing"], self.primary),
            [managed.WorktreeRecord("missing", None, "missing")],
        )
        created = add.add_worktree("feature", start=self.primary)
        _ = self.exclude().write_bytes(b"")
        (self.managed_root / ".gitignore").unlink()
        self.assertEqual(list_command.list_worktrees(["feature"], self.primary)[0].status, "unignored")
        _ = self.exclude().write_bytes(exclude.MANAGED_IGNORE_RULE + b"\n")
        shutil.rmtree(created / ".jj")
        self.assertEqual(list_command.list_worktrees(["feature"], self.primary)[0].status, "malformed")

    def test_reports_stale_git_record_without_reconstructing_its_path(self) -> None:
        created = add.add_worktree("feature", start=self.primary)
        shutil.rmtree(created)
        record = list_command.list_worktrees(["feature"], self.primary)[0]
        self.assertEqual(record, managed.WorktreeRecord("feature", created, "stale"))
        with self.assertRaisesRegex(process.WorktreeError, "stale"):
            _ = path_command.worktree_path("feature", self.primary)

    def test_reports_foreign_and_unmanaged_git_records(self) -> None:
        foreign = self.root / "foreign"
        _ = run("git", "-C", str(self.primary), "worktree", "add", "--detach", str(foreign), "HEAD")
        self.assertEqual(list_command.list_worktrees(["foreign"], self.primary)[0].status, "foreign")
        _ = init.initialize(self.primary)
        self.managed_root.mkdir(exist_ok=True)
        unmanaged = self.managed_root / "unmanaged"
        _ = run(
            "git",
            "-C",
            str(self.primary),
            "worktree",
            "add",
            "-b",
            "unmanaged-test",
            str(unmanaged),
            "HEAD",
        )
        self.assertEqual(list_command.list_worktrees(["unmanaged"], self.primary)[0].status, "attached")


@final
class AddErrorTests(CreatedFixture):
    def assert_rejected(self, name: str, revision: str | None = None) -> None:
        before = self.worktree_paths()
        with self.assertRaises(process.WorktreeError):
            _ = add.add_worktree(name, revision, self.primary)
        self.assertEqual(self.worktree_paths(), before)

    def test_rejects_unsafe_duplicate_absent_and_ambiguous_inputs(self) -> None:
        for name in ("", ".", "..", "nested/name", "line\nbreak"):
            with self.subTest(name=name):
                self.assert_rejected(name, "root()")
        self.assert_rejected("missing")
        self.assert_rejected("ambiguous", "root() | @")
        _ = add.add_worktree("feature", start=self.primary)
        self.assert_rejected("feature", "root()")

    def test_rejects_symlinked_root_and_unignored_destination(self) -> None:
        outside = self.root / "outside"
        outside.mkdir()
        self.managed_root.symlink_to(outside, target_is_directory=True)
        self.assert_rejected("linked", "root()")
        self.managed_root.unlink()
        with patch.object(exclude, "is_ignored", return_value=False):
            self.assert_rejected("unignored", "root()")

    def test_rejects_symlink_destination_foreign_start_and_outside_root(self) -> None:
        _ = init.initialize(self.primary)
        self.managed_root.mkdir(exist_ok=True)
        (self.managed_root / "linked").symlink_to(self.root / "missing")
        self.assert_rejected("linked", "@-")
        foreign = self.root / "foreign"
        _ = run("jj", "git", "init", "--colocate", str(foreign))
        with self.assertRaises(process.WorktreeError):
            _ = add.add_worktree("foreign", "root()", foreign)
        with (
            patch.object(repository, "MANAGED_ROOT_NAME", "../outside"),
            patch.object(managed, "MANAGED_ROOT_NAME", "../outside"),
        ):
            self.assert_rejected("outside", "@-")

    def test_rolls_back_failed_jj_initialization(self) -> None:
        with patch.object(
            managed,
            "validate_attached_jj",
            side_effect=process.WorktreeError("validation failed"),
        ):
            self.assert_rejected("rollback", "@-")
        self.assertFalse((self.managed_root / "rollback").exists())

    def test_reports_rollback_failure(self) -> None:
        with (
            patch.object(
                managed,
                "validate_attached_jj",
                side_effect=process.WorktreeError("validation failed"),
            ),
            patch.object(add, "_rollback_add", return_value="simulated cleanup failure"),
        ):
            with self.assertRaisesRegex(process.WorktreeError, "rollback failed"):
                _ = add.add_worktree("rollback-failure", "@-", self.primary)
        _ = run(
            "git",
            "-C",
            str(self.primary),
            "worktree",
            "remove",
            "--force",
            str(self.managed_root / "rollback-failure"),
        )

    def test_plain_git_failure_leaves_no_destination(self) -> None:
        destination = self.managed_root / "failed"
        real_run = process.run

        def fail_add(
            command: list[str] | tuple[str, ...],
            *,
            cwd: Path | None = None,
            input_data: bytes | None = None,
        ) -> subprocess.CompletedProcess[bytes]:
            if "worktree" in command and "add" in command:
                return subprocess.CompletedProcess(command, 1, b"", b"simulated failure")
            return real_run(command, cwd=cwd, input_data=input_data)

        with patch.object(process, "run", side_effect=fail_add):
            with self.assertRaises(process.WorktreeError):
                _ = add.add_worktree("failed", "@-", self.primary)
        self.assertFalse(destination.exists())
        created = add.add_worktree("failed", "@-", self.primary)
        self.assertEqual(created, destination)

    def test_failed_git_add_rolls_back_registered_destination(self) -> None:
        destination = self.managed_root / "partial"
        real_run = process.run

        def fail_after_add(
            command: list[str] | tuple[str, ...],
            *,
            cwd: Path | None = None,
            input_data: bytes | None = None,
        ) -> subprocess.CompletedProcess[bytes]:
            result = real_run(command, cwd=cwd, input_data=input_data)
            if "worktree" in command and "add" in command:
                return subprocess.CompletedProcess(command, 1, result.stdout, b"late failure")
            return result

        with patch.object(process, "run", side_effect=fail_after_add):
            with self.assertRaisesRegex(process.WorktreeError, "late failure"):
                _ = add.add_worktree("partial", "@-", self.primary)
        self.assertFalse(destination.exists())
        self.assertNotIn(destination, self.worktree_paths())


@final
class GitWorktreeIsolationTests(RepositoryFixture):
    def test_worktrees_have_private_git_state_and_shared_objects(self) -> None:
        first = self.create_linked("first")
        second = self.create_linked("second")
        primary_head = run("git", "-C", str(self.primary), "rev-parse", "HEAD").stdout
        primary_index = (self.primary / ".git" / "index").read_bytes()
        first_private = run(
            "git", "-C", str(first), "rev-parse", "--absolute-git-dir"
        ).stdout
        self.assertEqual(run("jj", "-R", str(first), "git", "root").stdout, first_private)
        first_head = run("git", "-C", str(first), "rev-parse", "HEAD").stdout
        _ = run("jj", "-R", str(first), "new")
        self.assertEqual(run("git", "-C", str(self.primary), "rev-parse", "HEAD").stdout, primary_head)
        self.assertEqual((self.primary / ".git" / "index").read_bytes(), primary_index)
        self.assertNotEqual(run("git", "-C", str(first), "rev-parse", "HEAD").stdout, first_head)
        self.assertEqual(
            run("git", "-C", str(first), "rev-parse", "--git-common-dir").stdout,
            run("git", "-C", str(second), "rev-parse", "--git-common-dir").stdout,
        )
        self.assertNotEqual(
            run("git", "-C", str(first), "rev-parse", "--absolute-git-dir").stdout,
            run("git", "-C", str(second), "rev-parse", "--absolute-git-dir").stdout,
        )


@final
class NixIsolationTests(RepositoryFixture):
    def test_nix_reads_each_worktree_filesystem(self) -> None:
        if shutil.which("nix") is None:
            self.skipTest("nix is unavailable")
        _ = (self.primary / "flake.nix").write_text(
            "{ outputs = { self }: { proof = builtins.readFile ./value; }; }\n"
        )
        _ = (self.primary / "value").write_text("primary")
        _ = run("jj", "-R", str(self.primary), "status")
        _ = run("jj", "-R", str(self.primary), "bookmark", "create", "nix-test", "-r", "@")
        linked = add.add_worktree("nix-test", start=self.primary)
        _ = (linked / "value").write_text("linked")
        cache = self.root / "cache"
        cache.mkdir()
        with patch.dict(
            os.environ,
            {"HOME": str(self.root), "XDG_CACHE_HOME": str(cache)},
        ):
            result = run("nix", "eval", "--raw", ".#proof", cwd=linked, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "linked")


@final
class OperationIsolationTests(RepositoryFixture):
    def test_operations_are_local_and_bookmark_handoff_uses_shared_refs(self) -> None:
        first = self.create_linked("first")
        second = self.create_linked("second")
        _ = run("jj", "-R", str(first), "describe", "-m", "first-only")
        first_private_op = run(
            "jj", "-R", str(first), "op", "log", "--no-graph", "-n", "1", "-T", "id"
        ).stdout.strip()
        _ = run("jj", "-R", str(first), "bookmark", "create", "handoff", "-r", "@")
        _ = run("jj", "-R", str(first), "git", "export")
        _ = run("jj", "-R", str(second), "git", "import")
        visible = run(
            "jj", "-R", str(second), "log", "--no-graph", "-r", "handoff", "-T", "description"
        ).stdout
        self.assertEqual(visible, "first-only\n")
        second_operations = run("jj", "-R", str(second), "op", "log", "--no-graph", "-T", "id").stdout
        self.assertNotIn(first_private_op, second_operations)
        second_head = run(
            "jj", "-R", str(second), "log", "--no-graph", "-r", "@", "-T", "commit_id"
        ).stdout
        _ = (first / "tracked").write_text("first anonymous change\n")
        _ = run("jj", "-R", str(first), "status")
        anonymous = run(
            "jj", "-R", str(first), "log", "--no-graph", "-r", "@", "-T", "commit_id"
        ).stdout
        visible_anonymous = run(
            "jj",
            "-R",
            str(second),
            "log",
            "--no-graph",
            "-r",
            "heads(all())",
            "-T",
            'commit_id ++ "\\n"',
        )
        self.assertIn(anonymous.strip(), visible_anonymous.stdout.splitlines())
        self.assertEqual(
            run("jj", "-R", str(second), "log", "--no-graph", "-r", "@", "-T", "commit_id").stdout,
            second_head,
        )
        _ = run("jj", "-R", str(first), "undo")
        self.assertEqual(
            run("jj", "-R", str(second), "log", "--no-graph", "-r", "@", "-T", "commit_id").stdout,
            second_head,
        )


class RemovalFixture(RepositoryFixture):
    created: Path

    @override
    def setUp(self) -> None:
        super().setUp()
        self.created = self.create_linked("feature")


@final
class RemoveTests(RemovalFixture):
    def test_removes_empty_undescribed_worktree_and_metadata(self) -> None:
        private = Path(
            run("git", "-C", str(self.created), "rev-parse", "--absolute-git-dir").stdout.strip()
        )
        remove.remove_worktree("feature", confirm=True, start=self.primary)
        self.assertFalse(self.created.exists())
        self.assertFalse(private.exists())
        self.assertNotIn(self.created, self.worktree_paths())


@final
class RemoveGuardTests(RemovalFixture):
    def test_requires_confirmation_and_refuses_current_worktree(self) -> None:
        with self.assertRaisesRegex(process.WorktreeError, "--yes"):
            remove.remove_worktree("feature", start=self.primary)
        with self.assertRaisesRegex(process.WorktreeError, "current"):
            remove.remove_worktree("feature", confirm=True, start=self.created)
        self.assertTrue(self.created.exists())

    def test_refuses_nonempty_described_and_dirty_worktrees(self) -> None:
        _ = (self.created / "tracked").write_text("changed\n")
        with self.assertRaises(process.WorktreeError):
            remove.remove_worktree("feature", confirm=True, start=self.primary)
        _ = (self.created / "tracked").write_text("initial\n")
        _ = run("jj", "-R", str(self.created), "status")
        _ = run("jj", "-R", str(self.created), "describe", "-m", "keep")
        with self.assertRaises(process.WorktreeError):
            remove.remove_worktree("feature", confirm=True, start=self.primary)
        self.assertTrue(self.created.exists())

    def test_refuses_unignored_or_malformed_identity(self) -> None:
        _ = self.exclude().write_bytes(b"")
        (self.managed_root / ".gitignore").unlink()
        with self.assertRaises(process.WorktreeError):
            remove.remove_worktree("feature", confirm=True, start=self.primary)
        self.assertTrue(self.created.exists())

    def test_refusal_does_not_run_destructive_commands(self) -> None:
        _ = run("jj", "-R", str(self.created), "describe", "-m", "preserve")
        real_run = process.run

        def reject_destructive_command(
            command: list[str] | tuple[str, ...],
            *,
            cwd: Path | None = None,
            input_data: bytes | None = None,
        ) -> subprocess.CompletedProcess[bytes]:
            if "remove" in command or "clean" in command:
                self.fail(f"refusal attempted destructive command: {command}")
            return real_run(command, cwd=cwd, input_data=input_data)

        with patch.object(process, "run", side_effect=reject_destructive_command):
            with self.assertRaises(process.WorktreeError):
                remove.remove_worktree("feature", confirm=True, start=self.primary)

    def test_refuses_symlink_replacement(self) -> None:
        displaced = self.root / "displaced"
        _ = self.created.rename(displaced)
        self.created.symlink_to(self.primary, target_is_directory=True)
        try:
            with self.assertRaises(process.WorktreeError):
                remove.remove_worktree("feature", confirm=True, start=self.primary)
            self.assertTrue(displaced.exists())
        finally:
            self.created.unlink()
            _ = displaced.rename(self.created)

    def test_refuses_malformed_and_foreign_records(self) -> None:
        shutil.rmtree(self.created / ".jj")
        worktrees = self.worktree_paths()
        with self.assertRaisesRegex(process.WorktreeError, "malformed"):
            remove.remove_worktree("feature", confirm=True, start=self.primary)
        self.assertEqual(self.worktree_paths(), worktrees)
        foreign = self.root / "foreign"
        _ = run("git", "-C", str(self.primary), "worktree", "add", "--detach", str(foreign), "HEAD")
        private = run("git", "-C", str(foreign), "rev-parse", "--absolute-git-dir").stdout.strip()
        _ = run("jj", "git", "init", f"--git-repo={private}", str(foreign))
        with self.assertRaisesRegex(process.WorktreeError, "foreign"):
            remove.remove_worktree("foreign", confirm=True, start=self.primary)
        self.assertTrue(foreign.exists())

    def test_refuses_repository_from_foreign_common_git_directory(self) -> None:
        shutil.rmtree(self.created)
        _ = run("jj", "git", "init", "--colocate", str(self.created))
        foreign_git = Path(
            run("git", "-C", str(self.created), "rev-parse", "--absolute-git-dir").stdout.strip()
        )
        with self.assertRaisesRegex(process.WorktreeError, "foreign"):
            remove.remove_worktree("feature", confirm=True, start=self.primary)
        self.assertTrue(self.created.exists())
        self.assertTrue(foreign_git.exists())
        self.assertIn(self.created, self.worktree_paths())

    def test_git_cleanliness_guard_is_independent(self) -> None:
        _ = (self.created / "git-only-dirty").write_text("dirty\n")
        with patch.object(remove, "_jj_working_copy_is_removable", return_value=None):
            with self.assertRaisesRegex(process.WorktreeError, "Git worktree has active changes"):
                remove.remove_worktree("feature", confirm=True, start=self.primary)
        self.assertTrue(self.created.exists())


@final
class RemoveFailureTests(RemovalFixture):
    def test_reports_git_failure_and_preserves_worktree(self) -> None:
        real_run = process.run

        def fail_remove(
            command: list[str] | tuple[str, ...],
            *,
            cwd: Path | None = None,
            input_data: bytes | None = None,
        ) -> subprocess.CompletedProcess[bytes]:
            if "remove" in command and "worktree" in command:
                return subprocess.CompletedProcess(command, 1, b"", b"simulated failure")
            return real_run(command, cwd=cwd, input_data=input_data)

        with patch.object(process, "run", side_effect=fail_remove):
            with self.assertRaisesRegex(
                process.WorktreeError,
                "files are present and metadata is present",
            ):
                remove.remove_worktree("feature", confirm=True, start=self.primary)
        self.assertTrue(self.created.exists())
        self.assertIn(self.created, self.worktree_paths())

    def test_reports_metadata_only_partial_failure(self) -> None:
        real_run = process.run

        def remove_files(
            command: list[str] | tuple[str, ...],
            *,
            cwd: Path | None = None,
            input_data: bytes | None = None,
        ) -> subprocess.CompletedProcess[bytes]:
            if "remove" in command and "worktree" in command:
                shutil.rmtree(self.created)
                return subprocess.CompletedProcess(command, 1, b"", b"partial")
            return real_run(command, cwd=cwd, input_data=input_data)

        with patch.object(process, "run", side_effect=remove_files):
            with self.assertRaisesRegex(
                process.WorktreeError,
                "files are missing and metadata is present",
            ):
                remove.remove_worktree("feature", confirm=True, start=self.primary)

    def test_reports_files_only_partial_failure(self) -> None:
        real_run = process.run

        def remove_metadata(
            command: list[str] | tuple[str, ...],
            *,
            cwd: Path | None = None,
            input_data: bytes | None = None,
        ) -> subprocess.CompletedProcess[bytes]:
            if "remove" in command and "worktree" in command:
                result = real_run(command, cwd=cwd, input_data=input_data)
                self.created.mkdir()
                return subprocess.CompletedProcess(command, 1, result.stdout, b"partial")
            return real_run(command, cwd=cwd, input_data=input_data)

        with patch.object(process, "run", side_effect=remove_metadata):
            with self.assertRaisesRegex(
                process.WorktreeError,
                "files are present and metadata is missing",
            ):
                remove.remove_worktree("feature", confirm=True, start=self.primary)

    def test_reports_incomplete_nominal_success(self) -> None:
        real_run = process.run

        def false_success(
            command: list[str] | tuple[str, ...],
            *,
            cwd: Path | None = None,
            input_data: bytes | None = None,
        ) -> subprocess.CompletedProcess[bytes]:
            if "remove" in command and "worktree" in command:
                return subprocess.CompletedProcess(command, 0, b"", b"")
            return real_run(command, cwd=cwd, input_data=input_data)

        with patch.object(process, "run", side_effect=false_success):
            with self.assertRaisesRegex(
                process.WorktreeError,
                "reported success; files are present and metadata is present",
            ):
                remove.remove_worktree("feature", confirm=True, start=self.primary)


@final
class HelpTests(unittest.TestCase):
    def test_help_documents_lifecycle_isolation_risk_and_clean_guard(self) -> None:
        help_text = cli.create_parser().format_help()
        for expected in (
            "init",
            "add",
            "path",
            "list",
            "remove",
            ".jj-worktrees",
            "detached",
            "independent jj operation and undo history",
            "bookmarks",
            "unsupported jj compatibility dependency",
            "git clean -fdx",
            "git clean -fdx -e '/.jj-worktrees/'",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, help_text)


if __name__ == "__main__":
    _ = unittest.main()
