#!/usr/bin/env python3
# pyright: reportImplicitRelativeImport=false, reportPrivateUsage=false
# pyright: reportUninitializedInstanceVariable=false

from __future__ import annotations

from collections.abc import MutableMapping
from contextlib import AbstractContextManager

import io
import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final, override
from unittest.mock import patch

from jj_ensure import cli


def run(*arguments: str, check: bool = True, cwd: Path | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(arguments, cwd=cwd, check=check, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


class RepositoryFixture(unittest.TestCase):
    temporary_directory: TemporaryDirectory[str]
    root: Path
    primary: Path

    @override
    def setUp(self) -> None:
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name).resolve()
        home = self.root / "home"
        (home / ".config").mkdir(parents=True)
        # `patch.dict` is untyped, so bind it to the context-manager protocol it
        # implements and let `enterContext` own the teardown; calling `start` and
        # `stop` through the unannotated value spreads Any into `addCleanup`.
        environment: AbstractContextManager[MutableMapping[str, str]] = patch.dict(
            os.environ,
            {
                "HOME": str(home),
                "XDG_CONFIG_HOME": str(home / ".config"),
                "XDG_CACHE_HOME": str(home / ".cache"),
                "XDG_STATE_HOME": str(home / ".state"),
            },
        )
        self.enterContext(environment)
        self.primary = self.root / "primary"
        self.primary.mkdir()
        _ = run("git", "init", str(self.primary))
        _ = run("git", "-C", str(self.primary), "config", "user.name", "Test User")
        _ = run("git", "-C", str(self.primary), "config", "user.email", "test@example.com")
        _ = (self.primary / "tracked").write_text("initial\n")
        _ = run("git", "-C", str(self.primary), "add", "tracked")
        _ = run("git", "-C", str(self.primary), "commit", "-m", "initial")

    def linked(self, name: str, *, branch: bool = False) -> Path:
        path = self.root / name
        arguments = ["git", "-C", str(self.primary), "worktree", "add"]
        arguments.extend(["-b", f"test-{name}"] if branch else ["--detach"])
        arguments.extend([str(path), "HEAD"])
        _ = run(*arguments)
        return path

    def private_git(self, path: Path) -> Path:
        return Path(run("git", "-C", str(path), "rev-parse", "--absolute-git-dir").stdout.decode().strip())

    def operation(self, path: Path) -> bytes:
        return run("jj", "-R", str(path), "op", "log", "--no-graph", "-n", "1", "-T", "id").stdout

    def jj_config(self, path: Path, key: str) -> str:
        return run("jj", "-R", str(path), "config", "get", key).stdout.decode().strip()

    def author_email(self, path: Path) -> str:
        return run(
            "jj", "-R", str(path), "log", "-r", "@", "--no-graph", "-T", "author.email()"
        ).stdout.decode().strip()

    def cloned_with_remote(self, name: str) -> tuple[Path, str]:
        bare = self.root / f"{name}.git"
        _ = run("git", "clone", "--bare", str(self.primary), str(bare))
        clone = self.root / name
        _ = run("git", "clone", str(bare), str(clone))
        _ = run("git", "-C", str(clone), "config", "user.name", "Test User")
        _ = run("git", "-C", str(clone), "config", "user.email", "test@example.com")
        head = run("git", "-C", str(clone), "symbolic-ref", "refs/remotes/origin/HEAD").stdout.decode().strip()
        return clone, head.rsplit("/", 1)[-1]

    def tracked(self, path: Path) -> str:
        return run("jj", "-R", str(path), "bookmark", "list", "--tracked").stdout.decode()


@final
class EnsureBehaviorTests(RepositoryFixture):
    def dry_run(self, path: Path) -> str:
        output = io.StringIO()
        with patch("sys.stdout", output):
            self.assertEqual(cli.main(["--dry-run", str(path)]), 0)
        return output.getvalue()

    def test_dry_run_reports_initialization_without_creating_jj(self) -> None:
        self.assertIn("would initialize colocated", self.dry_run(self.primary))
        self.assertFalse((self.primary / ".jj").exists())
        linked = self.linked("linked")
        self.assertIn("would initialize linked", self.dry_run(linked))
        self.assertFalse((linked / ".jj").exists())

    def test_rejects_git_lfs_before_initialization(self) -> None:
        _ = (self.primary / ".gitattributes").write_text("*.bin filter=lfs diff=lfs merge=lfs -text\n")
        with self.assertRaisesRegex(cli.EnsureError, "Git LFS is not supported by jj"):
            _ = cli.plan(self.primary)
        with self.assertRaisesRegex(cli.EnsureError, "Git LFS is not supported by jj"):
            _ = cli.ensure(self.primary)
        self.assertFalse((self.primary / ".jj").exists())

    def test_rejects_git_lfs_in_existing_workspace(self) -> None:
        _ = cli.ensure(self.primary)
        _ = (self.primary / ".gitattributes").write_text("[attr]media filter=lfs -text\n")
        with self.assertRaisesRegex(cli.EnsureError, "Git LFS is not supported by jj"):
            _ = cli.ensure(self.primary)

    def test_rejects_git_lfs_from_configured_global_attributes(self) -> None:
        attributes = self.root / "global-attributes"
        _ = attributes.write_text("*.bin filter=lfs\n")
        _ = run("git", "-C", str(self.primary), "config", "core.attributesFile", str(attributes))
        with self.assertRaisesRegex(cli.EnsureError, str(attributes)):
            _ = cli.ensure(self.primary)

    def test_resolves_relative_global_attributes_from_checkout(self) -> None:
        attributes = self.primary / "config" / "attributes"
        attributes.parent.mkdir()
        _ = attributes.write_text("*.bin filter=lfs\n")
        _ = run(
            "git",
            "-C",
            str(self.primary),
            "config",
            "core.attributesFile",
            "config/attributes",
        )
        with self.assertRaisesRegex(cli.EnsureError, str(attributes)):
            _ = cli.ensure(self.primary)

    def test_ignores_git_lfs_in_nested_repository(self) -> None:
        nested = self.primary / "nested"
        nested.mkdir()
        _ = run("git", "init", str(nested))
        _ = (nested / ".gitattributes").write_text("*.bin filter=lfs\n")
        self.assertEqual(cli.ensure(self.primary), self.primary)

    def test_dry_run_reports_noop_and_enrollment_without_writing_marker(self) -> None:
        _ = cli.ensure(self.primary)
        self.assertIn("no changes: compatible", self.dry_run(self.primary))
        linked = self.linked("legacy")
        private = self.private_git(linked)
        _ = run("jj", "git", "init", f"--git-repo={private}", ".", cwd=linked)
        marker = private / "jj-ensure-target"
        self.assertIn("would create linked-worktree identity marker", self.dry_run(linked))
        self.assertFalse(marker.exists())

    def test_dry_run_reports_eligible_repair_without_changing_targets(self) -> None:
        linked = self.linked("linked")
        _ = cli.ensure(linked)
        target = linked / ".jj" / "repo" / "store" / "git_target"
        stale = target.read_bytes()
        moved = self.root / "moved-primary"
        _ = self.primary.rename(moved)
        self.primary = moved
        _ = run("git", "-C", str(moved), "worktree", "repair")
        marker = self.private_git(linked) / "jj-ensure-target"
        marker_before = marker.read_bytes()
        output = self.dry_run(linked)
        self.assertIn("would repair eligible stale jj target", output)
        self.assertIn("post-write validation not run", output)
        self.assertEqual(target.read_bytes(), stale)
        self.assertEqual(marker.read_bytes(), marker_before)

    def test_initializes_primary_from_subdirectory_and_is_idempotent(self) -> None:
        nested = self.primary / "nested"
        nested.mkdir()
        self.assertEqual(cli.ensure(nested), self.primary)
        operation = self.operation(self.primary)
        jj_state = os.stat(self.primary / ".jj")
        self.assertEqual(cli.ensure(self.primary), self.primary)
        self.assertEqual(self.operation(self.primary), operation)
        self.assertTrue(os.path.samestat(os.stat(self.primary / ".jj"), jj_state))
        self.assertTrue(os.path.samefile(run("jj", "-R", str(self.primary), "git", "root").stdout.decode().strip(), self.primary / ".git"))

    def test_initializes_branch_and_detached_linked_worktrees(self) -> None:
        for branch in (False, True):
            linked = self.linked(f"linked-{branch}", branch=branch)
            symbolic_before = run("git", "-C", str(linked), "symbolic-ref", "-q", "HEAD", check=False).stdout
            self.assertEqual(cli.ensure(linked), linked)
            self.assertTrue(os.path.samefile(run("jj", "-R", str(linked), "git", "root").stdout.decode().strip(), self.private_git(linked)))
            self.assertEqual(run("git", "-C", str(linked), "symbolic-ref", "-q", "HEAD", check=False).stdout, symbolic_before)

    def test_resolves_symlink_and_survives_native_linked_move(self) -> None:
        linked = self.linked("linked")
        alias = self.root / "alias"
        alias.symlink_to(linked, target_is_directory=True)
        self.assertEqual(cli.ensure(alias), linked)
        moved = self.root / "moved-linked"
        _ = run("git", "-C", str(self.primary), "worktree", "move", str(linked), str(moved))
        self.assertEqual(cli.ensure(moved), moved)
        self.assertTrue(os.path.samefile(cli._jj_path(moved, "git", "root"), self.private_git(moved)))
        stale = (moved / ".jj" / "repo" / "store" / "git_target").read_bytes()
        moved_primary = self.root / "moved-primary"
        _ = self.primary.rename(moved_primary)
        self.primary = moved_primary
        _ = run("git", "-C", str(moved_primary), "worktree", "repair")
        self.assertEqual(cli.ensure(moved), moved)
        self.assertNotEqual((moved / ".jj" / "repo" / "store" / "git_target").read_bytes(), stale)

    def test_enrolls_compatible_legacy_attachment_without_changing_jj_state(self) -> None:
        linked = self.linked("legacy")
        private = self.private_git(linked)
        _ = run("jj", "git", "init", f"--git-repo={private}", ".", cwd=linked)
        operation = self.operation(linked)
        jj_state = os.stat(linked / ".jj")
        self.assertFalse((private / "jj-ensure-target").exists())
        self.assertEqual(cli.ensure(linked), linked)
        self.assertEqual(self.operation(linked), operation)
        self.assertTrue(os.path.samestat(os.stat(linked / ".jj"), jj_state))
        self.assertEqual((private / "jj-ensure-target").read_bytes(), os.fsencode(private))

    def test_preserves_dirty_files_and_linked_state(self) -> None:
        linked = self.linked("dirty")
        _ = (linked / "tracked").write_text("changed\n")
        _ = (linked / "untracked").write_text("untracked\n")
        contents = ((linked / "tracked").read_bytes(), (linked / "untracked").read_bytes())
        _ = cli.ensure(linked)
        operation = self.operation(linked)
        git_dir = self.private_git(linked)
        git_state = run("git", "-C", str(linked), "status", "--porcelain=v1", "-z").stdout
        _ = cli.ensure(linked)
        self.assertEqual(((linked / "tracked").read_bytes(), (linked / "untracked").read_bytes()), contents)
        self.assertEqual(run("git", "-C", str(linked), "status", "--porcelain=v1", "-z").stdout, git_state)
        self.assertEqual(self.operation(linked), operation)
        self.assertTrue(os.path.samefile(cli._jj_path(linked, "git", "root"), git_dir))

    def test_repairs_after_primary_move_without_reinitializing_jj(self) -> None:
        linked = self.linked("linked")
        _ = cli.ensure(linked)
        _ = run("jj", "-R", str(linked), "describe", "-m", "retained description")
        operation = self.operation(linked)
        target_file = linked / ".jj" / "repo" / "store" / "git_target"
        stale = target_file.read_bytes()
        moved = self.root / "moved-primary"
        _ = self.primary.rename(moved)
        self.primary = moved
        _ = run("git", "-C", str(moved), "worktree", "repair")
        self.assertEqual(target_file.read_bytes(), stale)
        self.assertEqual(cli.ensure(linked), linked)
        self.assertNotEqual(target_file.read_bytes(), stale)
        self.assertEqual(self.operation(linked), operation)
        description = run("jj", "-R", str(linked), "log", "-r", "@", "--no-graph", "-T", "description").stdout
        self.assertEqual(description, b"retained description\n")
        self.assertTrue(os.path.samefile(cli._jj_path(linked, "git", "root"), self.private_git(linked)))


    def test_mirrors_git_identity_into_linked_workspace_outside_scope(self) -> None:
        linked = self.linked("linked")
        self.assertEqual(cli.ensure(linked), linked)
        self.assertEqual(self.jj_config(linked, "user.email"), "test@example.com")
        self.assertEqual(self.jj_config(linked, "user.name"), "Test User")
        self.assertEqual(self.author_email(linked), "test@example.com")
        self.assertEqual(self.jj_config(linked, "signing.backend"), "none")
        self.assertEqual(self.jj_config(linked, "git.sign-on-push"), "false")

    def test_mirrors_ssh_signing_selection(self) -> None:
        key = self.root / "signing.pub"
        _ = key.write_text("ssh-ed25519 AAAA test\n")
        for name, value in (("commit.gpgSign", "true"), ("gpg.format", "ssh"), ("user.signingKey", str(key))):
            _ = run("git", "-C", str(self.primary), "config", name, value)
        linked = self.linked("signed")
        _ = cli.ensure(linked)
        self.assertEqual(self.jj_config(linked, "signing.backend"), "ssh")
        self.assertEqual(self.jj_config(linked, "signing.key"), str(key))
        self.assertEqual(self.jj_config(linked, "git.sign-on-push"), "true")

    def test_reconfigures_existing_workspace_without_rewriting_author(self) -> None:
        linked = self.linked("linked")
        _ = cli.ensure(linked)
        self.assertEqual(self.author_email(linked), "test@example.com")
        operation = self.operation(linked)
        _ = run("git", "-C", str(self.primary), "config", "user.email", "moved@example.com")
        self.assertEqual(cli.ensure(linked), linked)
        self.assertEqual(self.jj_config(linked, "user.email"), "moved@example.com")
        self.assertEqual(self.author_email(linked), "test@example.com")
        self.assertEqual(self.operation(linked), operation)

    def test_dry_run_reports_mirrored_identity_without_writing_config(self) -> None:
        output = io.StringIO()
        with patch("sys.stdout", output):
            self.assertEqual(cli.main(["--dry-run", str(self.primary)]), 0)
        self.assertIn("would mirror jj commit identity test@example.com (signing disabled)", output.getvalue())
        self.assertFalse((self.primary / ".jj").exists())

    def test_tracks_default_remote_bookmark_on_fresh_init(self) -> None:
        clone, branch = self.cloned_with_remote("clone")
        self.assertEqual(cli.ensure(clone), clone)
        tracked = self.tracked(clone)
        self.assertIn(f"{branch}:", tracked)
        self.assertIn("@origin:", tracked)

    def test_dry_run_predicts_default_remote_bookmark_before_init(self) -> None:
        clone, branch = self.cloned_with_remote("clone")
        output = io.StringIO()
        with patch("sys.stdout", output):
            self.assertEqual(cli.main(["--dry-run", str(clone)]), 0)
        self.assertIn(f"would track default remote bookmark {branch}@origin", output.getvalue())
        self.assertFalse((clone / ".jj").exists())

    def test_skips_tracking_without_remote_head(self) -> None:
        output = io.StringIO()
        with patch("sys.stdout", output):
            self.assertEqual(cli.main(["--dry-run", str(self.primary)]), 0)
        self.assertNotIn("would track", output.getvalue())
        self.assertEqual(cli.ensure(self.primary), self.primary)
        self.assertEqual(self.tracked(self.primary).strip(), "")

    def test_dry_run_detection_failure_warns_and_predicts_no_tracking(self) -> None:
        output = io.StringIO()
        error = io.StringIO()
        with (
            patch.object(cli, "_default_remote_bookmark", side_effect=cli.EnsureError("broken remote")),
            patch("sys.stdout", output),
            patch("sys.stderr", error),
        ):
            self.assertEqual(cli.main(["--dry-run", str(self.primary)]), 0)
        self.assertNotIn("would track", output.getvalue())
        self.assertIn("warning: could not determine default remote bookmark: broken remote", error.getvalue())
        self.assertFalse((self.primary / ".jj").exists())

    def test_default_remote_bookmark_prefers_origin_across_remotes(self) -> None:
        checkout = cli.discover(self.primary)
        for name, branch in (("origin", "main"), ("upstream", "dev")):
            _ = run("git", "-C", str(self.primary), "remote", "add", name, f"../{name}.git")
            _ = run("git", "-C", str(self.primary), "symbolic-ref", f"refs/remotes/{name}/HEAD", f"refs/remotes/{name}/{branch}")
        self.assertEqual(cli._default_remote_bookmark(checkout), "main@origin")

    def test_default_remote_bookmark_none_on_multi_remote_tie_without_origin(self) -> None:
        checkout = cli.discover(self.primary)
        for name in ("alpha", "beta"):
            _ = run("git", "-C", str(self.primary), "remote", "add", name, f"../{name}.git")
            _ = run("git", "-C", str(self.primary), "symbolic-ref", f"refs/remotes/{name}/HEAD", f"refs/remotes/{name}/main")
        self.assertIsNone(cli._default_remote_bookmark(checkout))

    def test_tracking_detection_failure_warns_without_failing_ensure(self) -> None:
        error = io.StringIO()
        with (
            patch.object(cli, "_default_remote_bookmark", side_effect=cli.EnsureError("broken remote")),
            patch("sys.stderr", error),
        ):
            self.assertEqual(cli.ensure(self.primary), self.primary)
        self.assertIn("warning: could not determine default remote bookmark: broken remote", error.getvalue())
        self.assertTrue((self.primary / ".jj").is_dir())

    def test_tracking_command_failure_warns_without_failing_ensure(self) -> None:
        error = io.StringIO()
        with (
            patch.object(cli, "_default_remote_bookmark", return_value="main@"),
            patch("sys.stderr", error),
        ):
            self.assertEqual(cli.ensure(self.primary), self.primary)
        self.assertIn("warning: could not track default remote bookmark main@", error.getvalue())
        self.assertTrue((self.primary / ".jj").is_dir())

    def test_does_not_retrack_after_manual_untrack(self) -> None:
        clone, branch = self.cloned_with_remote("clone")
        _ = cli.ensure(clone)
        _ = run("jj", "-R", str(clone), "bookmark", "untrack", f"{branch}@origin")
        self.assertEqual(self.tracked(clone).strip(), "")
        self.assertEqual(cli.ensure(clone), clone)
        self.assertEqual(self.tracked(clone).strip(), "")


@final
class EnsureSafetyTests(RepositoryFixture):
    def test_rejects_non_git_and_incompatible_jj_without_mutation(self) -> None:
        plain = self.root / "plain"
        plain.mkdir()
        with self.assertRaises(cli.EnsureError):
            _ = cli.ensure(plain)
        linked = self.linked("incompatible")
        jj = linked / ".jj"
        jj.mkdir()
        marker = jj / "keep"
        _ = marker.write_bytes(b"safe")
        with self.assertRaises(cli.EnsureError):
            _ = cli.ensure(linked)
        self.assertEqual(marker.read_bytes(), b"safe")

    def test_rejects_unregistered_linked_worktree_before_initialization(self) -> None:
        linked = self.linked("linked")
        with patch.object(cli, "_worktree_paths", return_value=[self.primary]):
            with self.assertRaisesRegex(cli.EnsureError, "not uniquely registered"):
                _ = cli.ensure(linked)
        self.assertFalse((linked / ".jj").exists())

    def test_rejects_existing_or_wrong_stale_target_without_mutation(self) -> None:
        linked = self.linked("linked")
        _ = cli.ensure(linked)
        target_file = linked / ".jj" / "repo" / "store" / "git_target"
        for value in (self.primary / ".git", Path("/missing/wrong/layout")):
            with self.subTest(value=value):
                original = os.fsencode(value)
                _ = target_file.write_bytes(original)
                with self.assertRaises(cli.EnsureError):
                    _ = cli.ensure(linked)
                self.assertEqual(target_file.read_bytes(), original)

    def test_rejects_malformed_target_and_mismatched_identity_without_mutation(self) -> None:
        linked = self.linked("linked")
        _ = cli.ensure(linked)
        target_file = linked / ".jj" / "repo" / "store" / "git_target"
        identity_file = self.private_git(linked) / "jj-ensure-target"
        for target, identity in (
            (b"relative-target", identity_file.read_bytes()),
            (
                b"/missing/primary/.git/worktrees/linked",
                b"/missing/different/.git/worktrees/linked",
            ),
        ):
            with self.subTest(target=target):
                _ = target_file.write_bytes(target)
                _ = identity_file.write_bytes(identity)
                before = (target_file.read_bytes(), identity_file.read_bytes())
                with self.assertRaises(cli.EnsureError):
                    _ = cli.ensure(linked)
                self.assertEqual((target_file.read_bytes(), identity_file.read_bytes()), before)

    def test_initialization_failure_removes_only_created_jj(self) -> None:
        linked = self.linked("linked")
        real_run = cli._run

        def fail(command: list[str] | tuple[str, ...], *, cwd: Path | None = None) -> bytes:
            if command[:3] == ["jj", "git", "init"]:
                assert cwd is not None
                (cwd / ".jj").mkdir()
                _ = (cwd / ".jj" / "partial").write_bytes(b"partial")
                raise cli.EnsureError("simulated failure")
            return real_run(command, cwd=cwd)

        with patch.object(cli, "_run", side_effect=fail):
            with self.assertRaisesRegex(cli.EnsureError, "simulated failure"):
                _ = cli.ensure(linked)
        self.assertFalse((linked / ".jj").exists())
        self.assertTrue((linked / ".git").exists())
        self.assertEqual((linked / "tracked").read_text(), "initial\n")

    def test_identity_enrollment_failure_cleans_up_and_can_retry(self) -> None:
        linked = self.linked("linked")
        _ = cli.ensure(linked)
        identity = self.private_git(linked) / "jj-ensure-target"
        identity.unlink()
        with patch("os.fsync", side_effect=OSError("simulated sync failure")):
            with self.assertRaisesRegex(cli.EnsureError, "simulated sync failure"):
                _ = cli.ensure(linked)
        self.assertFalse(identity.exists())
        self.assertEqual(cli.ensure(linked), linked)
        self.assertTrue(identity.is_file())

    def test_failed_atomic_write_preserves_target(self) -> None:
        linked = self.linked("linked")
        _ = cli.ensure(linked)
        target_file = linked / ".jj" / "repo" / "store" / "git_target"
        original = target_file.read_bytes()
        with patch("os.replace", side_effect=OSError("simulated write failure")):
            with self.assertRaisesRegex(cli.EnsureError, "atomically repair"):
                cli._write_target_atomic(target_file, Path("/replacement"))
        self.assertEqual(target_file.read_bytes(), original)

    def test_failed_post_repair_validation_restores_target(self) -> None:
        linked = self.linked("linked")
        _ = cli.ensure(linked)
        target_file = linked / ".jj" / "repo" / "store" / "git_target"
        stale = target_file.read_bytes()
        moved = self.root / "moved-primary"
        _ = self.primary.rename(moved)
        self.primary = moved
        _ = run("git", "-C", str(moved), "worktree", "repair")
        real_validate = cli._validate
        calls = 0

        def fail_after_repair(checkout: cli.GitCheckout) -> None:
            nonlocal calls
            calls += 1
            if calls > 1:
                raise cli.EnsureError("simulated validation failure")
            real_validate(checkout)

        with patch.object(cli, "_validate", side_effect=fail_after_repair):
            with self.assertRaisesRegex(cli.EnsureError, "restored stale target"):
                _ = cli.ensure(linked)
        self.assertEqual(target_file.read_bytes(), stale)


@final
class CliTests(unittest.TestCase):
    def test_cli_prints_only_canonical_root_and_concise_error(self) -> None:
        output = io.StringIO()
        error = io.StringIO()
        with (
            patch.object(cli, "plan", side_effect=AssertionError("live execution called plan")),
            patch.object(cli, "ensure", return_value=Path("/canonical")),
            patch("sys.stdout", output),
            patch("sys.stderr", error),
        ):
            self.assertEqual(cli.main(["target"]), 0)
        self.assertEqual(error.getvalue(), "")
        self.assertEqual(output.getvalue(), "/canonical\n")
        with patch.object(cli, "ensure", side_effect=cli.EnsureError("invalid target")), patch(
            "sys.stderr", error
        ):
            with self.assertRaises(SystemExit) as status:
                _ = cli.main([])
        self.assertEqual(status.exception.code, 1)
        self.assertEqual(error.getvalue(), "error: invalid target\n")

    def test_help_documents_compatibility_and_repair_order(self) -> None:
        help_text = cli.create_parser().format_help()
        self.assertIn("unsupported private-Git-directory", help_text)
        self.assertIn("git worktree repair", help_text)
        self.assertIn("operation history", help_text)
        self.assertIn("--dry-run", help_text)


if __name__ == "__main__":
    _ = unittest.main()
