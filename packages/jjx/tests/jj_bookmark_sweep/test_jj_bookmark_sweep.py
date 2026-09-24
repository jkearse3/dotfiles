#!/usr/bin/env python3

from __future__ import annotations

from contextlib import AbstractContextManager
from collections.abc import MutableMapping, Sequence
import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import cast, override
from unittest import mock

from jjx.commands import bookmark_sweep as cli


def run(
    *arguments: str, cwd: Path, check: bool = True
) -> subprocess.CompletedProcess[bytes]:
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
        environment: AbstractContextManager[MutableMapping[str, str]] = mock.patch.dict(
            os.environ,
            {
                "GIT_CONFIG_GLOBAL": os.devnull,
                "GIT_CONFIG_NOSYSTEM": "1",
                "XDG_CONFIG_HOME": str(self.repository / ".config"),
            },
        )
        _ = self.enterContext(environment)
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


class SweepTests(RepositoryFixture):
    """Verify bookmark sweeping behavior against real jj repositories."""

    def bookmark_names(self) -> list[str]:
        """Return the local bookmark names in the test repository."""
        return (
            run("jj", "bookmark", "list", "-T", 'name ++ "\\n"', cwd=self.repository)
            .stdout.decode()
            .splitlines()
        )

    def test_sweeps_a_complete_stack_and_deletes_its_bookmarks(self) -> None:
        """Sweeping to a stack tip moves trunk and removes the stack bookmarks."""
        for bookmark in ("one", "two", "three"):
            self.add_stack_commit(bookmark)
        tip = cli._resolve("three", cwd=self.repository)

        self.assertEqual(
            cli.sweep("main", "three", cwd=self.repository), ["one", "two", "three"]
        )

        self.assertEqual(cli._resolve("main", cwd=self.repository), tip)
        self.assertEqual(self.bookmark_names(), ["main"])

    def test_sweeps_only_through_the_target(self) -> None:
        """Sweeping to an intermediate revision leaves later work untouched."""
        for bookmark in ("one", "two", "three"):
            self.add_stack_commit(bookmark)
        second = cli._resolve("two", cwd=self.repository)

        self.assertEqual(cli.sweep("main", "two", cwd=self.repository), ["one", "two"])

        self.assertEqual(cli._resolve("main", cwd=self.repository), second)
        self.assertEqual(
            cli._resolve("three", cwd=self.repository),
            cli._resolve("@", cwd=self.repository),
        )

    def test_sweeps_to_an_unbookmarked_revision(self) -> None:
        """The target may be any revset, and passed bookmarks are still swept."""
        self.add_stack_commit("one")
        _ = run("jj", "new", cwd=self.repository)
        _ = run("jj", "describe", "-m", "unbookmarked", cwd=self.repository)
        target = cli._resolve("@", cwd=self.repository)

        self.assertEqual(cli.sweep("main", "@", cwd=self.repository), ["one"])

        self.assertEqual(cli._resolve("main", cwd=self.repository), target)
        self.assertEqual(self.bookmark_names(), ["main"])

    def test_moves_without_sweeping_when_no_bookmarks_are_passed(self) -> None:
        """A sweep that passes no bookmarks is a plain fast-forward."""
        _ = run("jj", "new", cwd=self.repository)
        _ = run("jj", "describe", "-m", "unbookmarked", cwd=self.repository)
        target = cli._resolve("@", cwd=self.repository)

        with mock.patch.object(cli, "_run", wraps=cli._run) as run_command:
            self.assertEqual(cli.sweep("main", "@", cwd=self.repository), [])

        self.assertEqual(cli._resolve("main", cwd=self.repository), target)
        for call in run_command.call_args_list:
            self.assertNotIn("delete", cast(Sequence[str], call.args[0]))

    def test_dry_run_preserves_bookmarks(self) -> None:
        """A dry run reports bookmarks without moving or deleting them."""
        self.add_stack_commit("one")

        self.assertEqual(
            cli.sweep("main", "one", dry_run=True, cwd=self.repository), ["one"]
        )

        self.assertNotEqual(
            cli._resolve("main", cwd=self.repository),
            cli._resolve("one", cwd=self.repository),
        )

    def test_cleanup_failure_restores_bookmark_in_repository(self) -> None:
        """A failed cleanup moves the bookmark back to its original commit."""
        self.add_stack_commit("one")
        original_target = cli._resolve("main", cwd=self.repository)
        run_command = cli._run

        def fail_cleanup(command: Sequence[str], *, cwd: Path | None = None) -> bytes:
            if command[:3] == ["jj", "bookmark", "delete"]:
                raise cli.SweepError("injected cleanup failure")
            return run_command(command, cwd=cwd)

        with (
            mock.patch.object(cli, "_run", side_effect=fail_cleanup),
            self.assertRaisesRegex(cli.SweepError, "restored its original target"),
        ):
            _ = cli.sweep("main", "one", cwd=self.repository)

        self.assertEqual(original_target, cli._resolve("main", cwd=self.repository))
        _ = cli._resolve("one", cwd=self.repository)

    def test_forgets_swept_bookmarks(self) -> None:
        """Local-only cleanup forgets every bookmark in the swept range."""
        self.add_stack_commit("one")
        tip = cli._resolve("one", cwd=self.repository)

        with mock.patch.object(cli, "_run", wraps=cli._run) as run_command:
            self.assertEqual(
                cli.sweep("main", "one", forget=True, cwd=self.repository), ["one"]
            )

        self.assertEqual(cli._resolve("main", cwd=self.repository), tip)
        run_command.assert_any_call(
            ["jj", "bookmark", "forget", "--", 'exact:"one"'], cwd=self.repository
        )
        self.assertEqual(self.bookmark_names(), ["main"])

    def test_deletes_multiple_bookmarks_on_one_revision(self) -> None:
        """Cleanup includes every local bookmark attached to a swept revision."""
        self.add_stack_commit("one")
        _ = run("jj", "bookmark", "create", "alias", "-r", "one", cwd=self.repository)

        self.assertEqual(
            cli.sweep("main", "one", cwd=self.repository), ["alias", "one"]
        )

        self.assertEqual(self.bookmark_names(), ["main"])

    def test_deletes_bookmarks_by_exact_name(self) -> None:
        """Sweeping does not expand glob metacharacters in bookmark names."""
        _ = run(
            "jj", "bookmark", "create", "one-other", "-r", "main", cwd=self.repository
        )
        unrelated = cli._resolve("one-other", cwd=self.repository)
        self.add_stack_commit("one*")

        self.assertEqual(
            cli.sweep("main", 'bookmarks(exact:"one*")', cwd=self.repository),
            ["one*"],
        )

        self.assertEqual(cli._resolve("one-other", cwd=self.repository), unrelated)

    def test_rejects_a_target_at_the_bookmark(self) -> None:
        """Sweeping requires the target to differ from the bookmark's commit."""
        with self.assertRaisesRegex(cli.SweepError, "already points to"):
            _ = cli.sweep("main", "main", cwd=self.repository)

    def test_rejects_a_divergent_target(self) -> None:
        """Sweeping rejects a target outside the bookmark's descendants."""
        self.add_stack_commit("one")
        _ = run("jj", "new", "main", cwd=self.repository)
        _ = run("jj", "describe", "-m", "other", cwd=self.repository)
        _ = run("jj", "bookmark", "create", "other", "-r", "@", cwd=self.repository)

        with self.assertRaisesRegex(cli.SweepError, "not a descendant"):
            _ = cli.sweep("one", "other", cwd=self.repository)

    def test_rejects_a_non_first_parent_stack_without_mutating_bookmarks(self) -> None:
        """A rejected merge topology leaves the bookmark and stack intact."""
        self.add_stack_commit("one")
        one = cli._resolve("one", cwd=self.repository)
        _ = run("jj", "new", "main", cwd=self.repository)
        _ = run("jj", "describe", "-m", "side", cwd=self.repository)
        _ = run("jj", "bookmark", "create", "side", "-r", "@", cwd=self.repository)
        _ = run("jj", "new", "one", "side", cwd=self.repository)
        _ = run("jj", "describe", "-m", "merge", cwd=self.repository)
        _ = run("jj", "bookmark", "create", "merge", "-r", "@", cwd=self.repository)

        with self.assertRaisesRegex(cli.SweepError, "first-parent stack"):
            _ = cli.sweep("main", "merge", cwd=self.repository)

        self.assertNotEqual(cli._resolve("main", cwd=self.repository), one)
        self.assertEqual(self.bookmark_names(), ["main", "merge", "one", "side"])

    def test_rejects_a_bookmark_revision(self) -> None:
        """Sweeping requires the moved argument to name a local bookmark."""
        self.add_stack_commit("one")

        with self.assertRaisesRegex(cli.SweepError, "not a local bookmark: @-"):
            _ = cli.sweep("@-", "one", cwd=self.repository)

    def test_accepts_jj_style_target_options(self) -> None:
        """The CLI accepts jj's short and long target option names."""
        parser = cli.create_parser()

        short_options = parser.parse_args(["main", "-t", "feature"])
        long_options = parser.parse_args(["main", "--to", "feature"])

        self.assertEqual(cast(str, short_options.to), "feature")
        self.assertEqual(cast(str, long_options.to), "feature")

    def test_requires_explicit_bookmark_and_target_arguments(self) -> None:
        """The CLI does not infer the bookmark or target from repository state."""
        parser = cli.create_parser()

        with self.assertRaises(SystemExit):
            _ = parser.parse_args([])
        with self.assertRaises(SystemExit):
            _ = parser.parse_args(["main"])


@mock.patch.object(cli, "_resolve_bookmark", return_value="base")
@mock.patch.object(cli, "_resolve", return_value="tip")
@mock.patch.object(cli, "_has_revisions", side_effect=[True, False, False])
@mock.patch.object(cli, "_lines", return_value=['"topic"'])
class AtomicSweepTests(unittest.TestCase):
    def test_cleanup_failure_restores_bookmark(
        self,
        _lines: mock.Mock,
        _has_revisions: mock.Mock,
        _resolve: mock.Mock,
        _resolve_bookmark: mock.Mock,
    ) -> None:
        with (
            mock.patch.object(cli, "_run", side_effect=cli.SweepError("cleanup failed")),
            mock.patch.object(cli, "_move_bookmark") as move,
            self.assertRaisesRegex(cli.SweepError, "restored its original target"),
        ):
            _ = cli.sweep("main", "topic")
        self.assertEqual(
            [
                mock.call("main", "tip", cwd=None),
                mock.call("main", "base", allow_backwards=True, cwd=None),
            ],
            move.call_args_list,
        )

    def test_cleanup_and_rollback_failure_reports_both_errors(
        self,
        _lines: mock.Mock,
        _has_revisions: mock.Mock,
        _resolve: mock.Mock,
        _resolve_bookmark: mock.Mock,
    ) -> None:
        with (
            mock.patch.object(cli, "_run", side_effect=cli.SweepError("cleanup failed")),
            mock.patch.object(
                cli,
                "_move_bookmark",
                side_effect=[None, cli.SweepError("rollback failed")],
            ),
            self.assertRaisesRegex(cli.SweepError, "rollback also failed"),
        ):
            _ = cli.sweep("main", "topic")


if __name__ == "__main__":
    _ = unittest.main()
