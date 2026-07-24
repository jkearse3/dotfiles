#!/usr/bin/env python3
# pyright: reportImplicitRelativeImport=false, reportPrivateUsage=false
# pyright: reportUninitializedInstanceVariable=false

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import override
from unittest import mock

from jj_bookmark_land import cli


def run(*arguments: str, cwd: Path, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    """Run a command in the test repository and capture its output."""
    return subprocess.run(
        arguments,
        cwd=cwd,
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


class RepositoryFixture(unittest.TestCase):
    """Provide each test with a temporary colocated Git and jj repository."""

    temporary_directory: TemporaryDirectory[str]
    repository: Path

    @override
    def setUp(self) -> None:
        """Create and initialize the temporary repository."""
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.repository = Path(self.temporary_directory.name).resolve()
        _ = run("git", "init", "-b", "main", ".", cwd=self.repository)
        _ = run("git", "config", "user.name", "Test User", cwd=self.repository)
        _ = run("git", "config", "user.email", "test@example.com", cwd=self.repository)
        _ = (self.repository / "tracked").write_text("initial\n")
        _ = run("git", "add", "tracked", cwd=self.repository)
        _ = run("git", "commit", "-m", "initial", cwd=self.repository)
        _ = run("jj", "git", "init", "--colocate", ".", cwd=self.repository)

    def add_stack_commit(self, bookmark: str) -> None:
        """Append a described revision carrying BOOKMARK to the test stack."""
        _ = run("jj", "new", cwd=self.repository)
        _ = run("jj", "describe", "-m", bookmark, cwd=self.repository)
        _ = run("jj", "bookmark", "create", bookmark, "-r", "@", cwd=self.repository)


class LandTests(RepositoryFixture):
    """Verify stack landing behavior against real jj repositories."""

    def test_lands_a_complete_stack_and_deletes_its_bookmarks(self) -> None:
        """Landing a complete stack moves trunk and removes stack bookmarks."""
        for bookmark in ("one", "two", "three"):
            self.add_stack_commit(bookmark)
        tip = cli._resolve("three", cwd=self.repository)

        self.assertEqual(cli.land("three", "main", cwd=self.repository), ["one", "two", "three"])

        self.assertEqual(cli._resolve("main", cwd=self.repository), tip)
        remaining = run(
            "jj",
            "bookmark",
            "list",
            "-T",
            'name ++ "\\n"',
            cwd=self.repository,
        ).stdout.decode().splitlines()
        self.assertEqual(remaining, ["main"])

    def test_lands_only_through_the_selected_tip(self) -> None:
        """Landing through an intermediate tip leaves later work untouched."""
        for bookmark in ("one", "two", "three"):
            self.add_stack_commit(bookmark)
        second = cli._resolve("two", cwd=self.repository)

        self.assertEqual(cli.land("two", "main", cwd=self.repository), ["one", "two"])

        self.assertEqual(cli._resolve("main", cwd=self.repository), second)
        self.assertEqual(cli._resolve("three", cwd=self.repository), cli._resolve("@", cwd=self.repository))

    def test_dry_run_preserves_bookmarks(self) -> None:
        """A dry run reports bookmarks without moving or deleting them."""
        self.add_stack_commit("one")

        self.assertEqual(cli.land("one", "main", dry_run=True, cwd=self.repository), ["one"])

        self.assertNotEqual(cli._resolve("main", cwd=self.repository), cli._resolve("one", cwd=self.repository))

    def test_forgets_landed_bookmarks(self) -> None:
        """Local-only cleanup forgets every bookmark in the landed range."""
        self.add_stack_commit("one")
        tip = cli._resolve("one", cwd=self.repository)

        with mock.patch.object(cli, "_run", wraps=cli._run) as run_command:
            self.assertEqual(cli.land("one", "main", forget=True, cwd=self.repository), ["one"])

        self.assertEqual(cli._resolve("main", cwd=self.repository), tip)
        run_command.assert_any_call(
            ["jj", "bookmark", "forget", "--", 'exact:"one"'], cwd=self.repository
        )
        bookmarks = run(
            "jj", "bookmark", "list", "-T", 'name ++ "\\n"', cwd=self.repository
        ).stdout.decode().splitlines()
        self.assertEqual(bookmarks, ["main"])

    def test_deletes_multiple_bookmarks_on_one_revision(self) -> None:
        """Cleanup includes every local bookmark attached to a landed revision."""
        self.add_stack_commit("one")
        _ = run("jj", "bookmark", "create", "alias", "-r", "one", cwd=self.repository)

        self.assertEqual(cli.land("one", "main", cwd=self.repository), ["alias", "one"])

        bookmarks = run(
            "jj", "bookmark", "list", "-T", 'name ++ "\\n"', cwd=self.repository
        ).stdout.decode().splitlines()
        self.assertEqual(bookmarks, ["main"])

    def test_deletes_bookmarks_by_exact_name(self) -> None:
        """Landing does not expand glob metacharacters in bookmark names."""
        _ = run("jj", "bookmark", "create", "one-other", "-r", "main", cwd=self.repository)
        unrelated = cli._resolve("one-other", cwd=self.repository)
        self.add_stack_commit("one*")

        self.assertEqual(cli.land("one*", "main", cwd=self.repository), ["one*"])

        self.assertEqual(cli._resolve("one-other", cwd=self.repository), unrelated)

    def test_rejects_a_divergent_tip(self) -> None:
        """Landing rejects a tip outside the destination's descendants."""
        self.add_stack_commit("one")
        _ = run("jj", "new", "main", cwd=self.repository)
        _ = run("jj", "describe", "-m", "other", cwd=self.repository)
        _ = run("jj", "bookmark", "create", "other", "-r", "@", cwd=self.repository)

        with self.assertRaisesRegex(cli.LandError, "not a descendant"):
            _ = cli.land("other", "one", cwd=self.repository)

    def test_rejects_a_non_first_parent_stack_without_mutating_bookmarks(self) -> None:
        """A rejected merge topology leaves the destination and stack intact."""
        self.add_stack_commit("one")
        one = cli._resolve("one", cwd=self.repository)
        _ = run("jj", "new", "main", cwd=self.repository)
        _ = run("jj", "describe", "-m", "side", cwd=self.repository)
        _ = run("jj", "bookmark", "create", "side", "-r", "@", cwd=self.repository)
        _ = run("jj", "new", "one", "side", cwd=self.repository)
        _ = run("jj", "describe", "-m", "merge", cwd=self.repository)
        _ = run("jj", "bookmark", "create", "merge", "-r", "@", cwd=self.repository)

        with self.assertRaisesRegex(cli.LandError, "first-parent stack"):
            _ = cli.land("merge", "main", cwd=self.repository)

        self.assertNotEqual(cli._resolve("main", cwd=self.repository), one)
        bookmarks = run(
            "jj", "bookmark", "list", "-T", 'name ++ "\\n"', cwd=self.repository
        ).stdout.decode().splitlines()
        self.assertEqual(bookmarks, ["main", "merge", "one", "side"])

    def test_rejects_a_tip_revision(self) -> None:
        """Landing requires the tip argument to name a local bookmark."""
        self.add_stack_commit("one")

        with self.assertRaisesRegex(cli.LandError, "tip must be a local bookmark: @"):
            _ = cli.land("@", "main", cwd=self.repository)

    def test_rejects_a_destination_revision(self) -> None:
        """Landing requires the destination argument to name a local bookmark."""
        self.add_stack_commit("one")

        with self.assertRaisesRegex(cli.LandError, "destination must be a local bookmark: @-"):
            _ = cli.land("one", "@-", cwd=self.repository)

    def test_requires_explicit_tip_and_destination_arguments(self) -> None:
        """The CLI does not infer either bookmark from repository state."""
        parser = cli.create_parser()

        with self.assertRaises(SystemExit):
            _ = parser.parse_args([])
        with self.assertRaises(SystemExit):
            _ = parser.parse_args(["feature"])


if __name__ == "__main__":
    _ = unittest.main()
