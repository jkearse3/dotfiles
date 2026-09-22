#!/usr/bin/env python3
# pyright: reportImplicitRelativeImport=false, reportPrivateUsage=false
# pyright: reportUninitializedInstanceVariable=false

from __future__ import annotations

import os
import subprocess
import unittest
from datetime import UTC, datetime
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final
from unittest.mock import patch

from jj_bookmark_backup import cli


FEATURE_BOOKMARK = "feature/api-redesign"
BACKUP_TIME = datetime(2026, 9, 22, 2, 5, 2, tzinfo=UTC)
BACKUP_BOOKMARK = "backup-20260922T020502Z/feature/api-redesign"


def run(
    *arguments: str,
    cwd: Path,
    check: bool = True,
) -> subprocess.CompletedProcess[bytes]:
    """Run a command in a test repository and capture its output."""
    return subprocess.run(
        arguments,
        cwd=cwd,
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


class RepositoryFixture(unittest.TestCase):
    """Provide a remote branch and a disposable cloned jj repository."""

    temporary_directory: TemporaryDirectory[str]
    root: Path
    repository: Path
    remote: Path

    def setUp(self) -> None:
        """Create the remote history and clone it through jj."""
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name).resolve()
        self.remote = self.root / "remote.git"
        self.repository = self.root / "repository"
        seed = self.root / "seed"

        home = self.root / "home"
        home.mkdir()
        home_patch = patch.dict(os.environ, {"HOME": str(home)})
        _ = home_patch.start()
        self.addCleanup(home_patch.stop)

        _ = run("git", "init", "--bare", "-b", "main", str(self.remote), cwd=self.root)
        _ = run("git", "init", "-b", "main", str(seed), cwd=self.root)
        _ = run("git", "config", "user.name", "Test User", cwd=seed)
        _ = run("git", "config", "user.email", "test@example.com", cwd=seed)
        _ = (seed / "tracked").write_text("initial\n")
        _ = run("git", "add", "tracked", cwd=seed)
        _ = run("git", "commit", "-m", "initial", cwd=seed)
        _ = run("git", "checkout", "-qb", FEATURE_BOOKMARK, cwd=seed)
        _ = (seed / "one").write_text("one\n")
        _ = run("git", "add", "one", cwd=seed)
        _ = run("git", "commit", "-m", "feature one", cwd=seed)
        _ = (seed / "two").write_text("two\n")
        _ = run("git", "add", "two", cwd=seed)
        _ = run("git", "commit", "-m", "feature two", cwd=seed)
        _ = run("git", "remote", "add", "origin", str(self.remote), cwd=seed)
        _ = run("git", "push", "-u", "origin", "main", FEATURE_BOOKMARK, cwd=seed)
        _ = run("jj", "git", "clone", str(self.remote), str(self.repository), cwd=self.root)

        _ = run("jj", "config", "set", "--repo", "user.name", "Test User", cwd=self.repository)
        _ = run(
            "jj",
            "config",
            "set",
            "--repo",
            "user.email",
            "test@example.com",
            cwd=self.repository,
        )
        _ = run(
            "jj",
            "config",
            "set",
            "--repo",
            "git.private-commits",
            'bookmarks(glob:"backup-*")',
            cwd=self.repository,
        )
        _ = run(
            "jj",
            "config",
            "set",
            "--repo",
            "remotes.origin.auto-track-created-bookmarks",
            '"*"',
            cwd=self.repository,
        )
        _ = run(
            "jj",
            "bookmark",
            "track",
            FEATURE_BOOKMARK,
            "--remote",
            "origin",
            cwd=self.repository,
        )

    def jj_output(self, *arguments: str) -> str:
        """Run jj successfully and return decoded stdout."""
        return run("jj", *arguments, cwd=self.repository).stdout.decode()

    def rewrite_feature(self) -> None:
        """Rewrite the feature stack while retaining its original change IDs."""
        first_commit = self.jj_output(
            "log",
            "--no-graph",
            "-r",
            f'roots(main..bookmarks(exact:"{FEATURE_BOOKMARK}"))',
            "-T",
            "commit_id",
        )
        _ = run(
            "jj",
            "describe",
            "-r",
            first_commit,
            "-m",
            "feature one rewritten",
            cwd=self.repository,
        )


@final
class BookmarkBackupTests(RepositoryFixture):
    """Verify backup behavior against real local and remote repositories."""

    def test_duplicates_rewritten_remote_history_without_divergence(self) -> None:
        """A rewritten remote stack is preserved under fresh change IDs."""
        self.rewrite_feature()

        backup = cli.create_backup(
            FEATURE_BOOKMARK,
            created_at=BACKUP_TIME,
            cwd=self.repository,
        )

        self.assertEqual(backup, BACKUP_BOOKMARK)
        backup_revset = f'bookmarks(exact:"{backup}")'
        backup_change_ids = set(
            self.jj_output("log", "--no-graph", "-r", f"main..{backup_revset}", "-T", 'change_id ++ "\\n"').splitlines()
        )
        remote_change_ids = set(
            self.jj_output(
                "log",
                "--no-graph",
                "-r",
                f'main..remote_bookmarks(exact:"{FEATURE_BOOKMARK}", exact:"origin")',
                "-T",
                'change_id ++ "\\n"',
            ).splitlines()
        )
        self.assertEqual(len(backup_change_ids), 2)
        self.assertEqual(len(remote_change_ids), 2)
        self.assertTrue(backup_change_ids.isdisjoint(remote_change_ids))
        self.assertEqual(
            self.jj_output(
                "diff",
                "--from",
                f"{FEATURE_BOOKMARK}@origin",
                "--to",
                backup_revset,
                "--summary",
            ),
            "",
        )
        self.assertEqual(
            self.jj_output(
                "bookmark",
                "list",
                "--tracked",
                "--remote",
                "exact:origin",
                "--template",
                'if(remote, name ++ "\\n")',
                "--",
                f"exact:{backup}",
            ),
            "",
        )

        push_all = run("jj", "git", "push", "--remote", "origin", "--all", cwd=self.repository)
        self.assertIn("private", (push_all.stdout + push_all.stderr).decode())
        self.assertEqual(
            self.jj_output(
                "bookmark",
                "list",
                "--remote",
                "exact:origin",
                "--template",
                'if(remote, name ++ "\\n")',
                "--",
                f"exact:{backup}",
            ),
            "",
        )

        target_before_push = self.jj_output("log", "--no-graph", "-r", backup_revset, "-T", "commit_id")
        _ = run(
            "jj",
            "git",
            "push",
            "--remote",
            "origin",
            "--bookmark",
            f"exact:{FEATURE_BOOKMARK}",
            cwd=self.repository,
        )
        target_after_push = self.jj_output("log", "--no-graph", "-r", backup_revset, "-T", "commit_id")

        self.assertEqual(target_after_push, target_before_push)
        self.assertEqual(self.jj_output("log", "--no-graph", "-r", "divergent()", "-T", "commit_id"), "")

    def test_reuses_a_remote_target_already_reachable_from_local_history(self) -> None:
        """A non-divergent remote target needs no duplicated revisions."""
        remote_target = self.jj_output(
            "log", "--no-graph", "-r", f"{FEATURE_BOOKMARK}@origin", "-T", "commit_id"
        )

        backup = cli.create_backup(
            FEATURE_BOOKMARK,
            created_at=BACKUP_TIME,
            cwd=self.repository,
        )

        backup_target = self.jj_output(
            "log", "--no-graph", "-r", f'bookmarks(exact:"{backup}")', "-T", "commit_id"
        )
        self.assertEqual(backup, BACKUP_BOOKMARK)
        self.assertEqual(backup_target, remote_target)

    def test_backs_up_a_remote_bookmark_without_a_local_bookmark(self) -> None:
        """A remote-only branch is duplicated relative to trunk."""
        _ = run(
            "jj",
            "bookmark",
            "untrack",
            FEATURE_BOOKMARK,
            "--remote",
            "origin",
            cwd=self.repository,
        )
        _ = run("jj", "bookmark", "forget", FEATURE_BOOKMARK, cwd=self.repository)

        backup = cli.create_backup(
            FEATURE_BOOKMARK,
            created_at=BACKUP_TIME,
            cwd=self.repository,
        )

        local_bookmark = self.jj_output(
            "bookmark",
            "list",
            "--template",
            'if(!remote, name ++ "\\n")',
            "--",
            f"exact:{FEATURE_BOOKMARK}",
        )
        backup_change_ids = set(
            self.jj_output(
                "log",
                "--no-graph",
                "-r",
                f'main..bookmarks(exact:"{backup}")',
                "-T",
                'change_id ++ "\\n"',
            ).splitlines()
        )
        remote_change_ids = set(
            self.jj_output(
                "log",
                "--no-graph",
                "-r",
                f'main..remote_bookmarks(exact:"{FEATURE_BOOKMARK}", exact:"origin")',
                "-T",
                'change_id ++ "\\n"',
            ).splitlines()
        )

        self.assertEqual(backup, BACKUP_BOOKMARK)
        self.assertEqual(local_bookmark, "")
        self.assertEqual(len(backup_change_ids), 2)
        self.assertTrue(backup_change_ids.isdisjoint(remote_change_ids))

    def test_parser_defaults_to_origin(self) -> None:
        """The CLI accepts one bookmark and defaults its source remote."""
        arguments = cli.create_parser().parse_args([FEATURE_BOOKMARK])

        self.assertEqual(arguments.bookmark, FEATURE_BOOKMARK)
        self.assertEqual(arguments.remote, "origin")


if __name__ == "__main__":
    _ = unittest.main()
