#!/usr/bin/env python3

from __future__ import annotations

import contextlib
from contextlib import AbstractContextManager
from collections.abc import MutableMapping, Sequence
import io
import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import cast, override
from unittest import mock

from jjx.commands import bookmark_land as cli


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


class LandTests(RepositoryFixture):
    """Verify bookmark landing behavior against real jj repositories."""

    def bookmark_names(self) -> list[str]:
        """Return the local bookmark names in the test repository."""
        return (
            run("jj", "bookmark", "list", "-T", 'name ++ "\\n"', cwd=self.repository)
            .stdout.decode()
            .splitlines()
        )

    def bookmark_state(self) -> str:
        """Return every local and remote bookmark with its target."""
        return run("jj", "bookmark", "list", "--all", cwd=self.repository).stdout.decode()

    def short_change_id(self, revision: str) -> str:
        """Return the short change ID jj shows for REVISION."""
        return run(
            "jj", "log", "--no-graph", "-r", revision, "-T", "change_id.short()",
            cwd=self.repository,
        ).stdout.decode()  # fmt: skip

    def set_advance_target(self, revset: str) -> None:
        """Set the repository's revsets.bookmark-advance-to to REVSET."""
        _ = run(
            "jj", "config", "set", "--repo", "revsets.bookmark-advance-to", revset,
            cwd=self.repository,
        )  # fmt: skip

    def add_origin(self) -> None:
        """Publish the repository's bookmarks to a local `origin` remote and fetch them."""
        origin_directory = TemporaryDirectory()
        self.addCleanup(origin_directory.cleanup)
        origin = Path(origin_directory.name) / "origin.git"
        _ = run("git", "clone", "--bare", ".", str(origin), cwd=self.repository)
        _ = run("jj", "git", "remote", "add", "origin", str(origin), cwd=self.repository)
        _ = run("jj", "git", "fetch", "--remote", "origin", cwd=self.repository)

    def test_lands_a_complete_stack_and_deletes_its_bookmarks(self) -> None:
        """Landing a stack tip moves trunk and removes the stack bookmarks."""
        for bookmark in ("one", "two", "three"):
            self.add_stack_commit(bookmark)
        tip = cli._resolve("three", cwd=self.repository)

        self.assertEqual(
            cli.land("three", "main", cwd=self.repository), ["one", "two", "three"]
        )

        self.assertEqual(cli._resolve("main", cwd=self.repository), tip)
        self.assertEqual(self.bookmark_names(), ["main"])

    def test_lands_only_through_the_target(self) -> None:
        """Landing an intermediate revision leaves later work untouched."""
        for bookmark in ("one", "two", "three"):
            self.add_stack_commit(bookmark)
        second = cli._resolve("two", cwd=self.repository)

        self.assertEqual(cli.land("two", "main", cwd=self.repository), ["one", "two"])

        self.assertEqual(cli._resolve("main", cwd=self.repository), second)
        self.assertEqual(
            cli._resolve("three", cwd=self.repository),
            cli._resolve("@", cwd=self.repository),
        )

    def test_lands_an_unbookmarked_revision(self) -> None:
        """The target may be any revset, and passed bookmarks are still removed."""
        self.add_stack_commit("one")
        _ = run("jj", "new", cwd=self.repository)
        _ = run("jj", "describe", "-m", "unbookmarked", cwd=self.repository)
        target = cli._resolve("@", cwd=self.repository)

        self.assertEqual(cli.land("@", "main", cwd=self.repository), ["one"])

        self.assertEqual(cli._resolve("main", cwd=self.repository), target)
        self.assertEqual(self.bookmark_names(), ["main"])

    def test_moves_without_deleting_when_no_bookmarks_are_passed(self) -> None:
        """A land that passes no bookmarks is a plain fast-forward."""
        _ = run("jj", "new", cwd=self.repository)
        _ = run("jj", "describe", "-m", "unbookmarked", cwd=self.repository)
        target = cli._resolve("@", cwd=self.repository)

        with mock.patch.object(cli, "_run", wraps=cli._run) as run_command:
            self.assertEqual(cli.land("@", "main", cwd=self.repository), [])

        self.assertEqual(cli._resolve("main", cwd=self.repository), target)
        for call in run_command.call_args_list:
            self.assertNotIn("delete", cast(Sequence[str], call.args[0]))

    def test_dry_run_preserves_bookmarks(self) -> None:
        """A dry run reports bookmarks without moving or deleting them."""
        self.add_stack_commit("one")

        self.assertEqual(
            cli.land("one", "main", dry_run=True, cwd=self.repository), ["one"]
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
                raise cli.LandError("injected cleanup failure")
            return run_command(command, cwd=cwd)

        with (
            mock.patch.object(cli, "_run", side_effect=fail_cleanup),
            self.assertRaisesRegex(cli.LandError, "restored its original target"),
        ):
            _ = cli.land("one", "main", cwd=self.repository)

        self.assertEqual(original_target, cli._resolve("main", cwd=self.repository))
        _ = cli._resolve("one", cwd=self.repository)

    def test_forgets_passed_bookmarks(self) -> None:
        """Local-only cleanup forgets every bookmark in the landed range."""
        self.add_stack_commit("one")
        tip = cli._resolve("one", cwd=self.repository)

        with mock.patch.object(cli, "_run", wraps=cli._run) as run_command:
            self.assertEqual(
                cli.land("one", "main", forget=True, cwd=self.repository), ["one"]
            )

        self.assertEqual(cli._resolve("main", cwd=self.repository), tip)
        run_command.assert_any_call(
            ["jj", "bookmark", "forget", "--", 'exact:"one"'], cwd=self.repository
        )
        self.assertEqual(self.bookmark_names(), ["main"])

    def test_deletes_multiple_bookmarks_on_one_revision(self) -> None:
        """Cleanup includes every local bookmark attached to a landed revision."""
        self.add_stack_commit("one")
        _ = run("jj", "bookmark", "create", "alias", "-r", "one", cwd=self.repository)

        self.assertEqual(
            cli.land("one", "main", cwd=self.repository), ["alias", "one"]
        )

        self.assertEqual(self.bookmark_names(), ["main"])

    def test_deletes_bookmarks_by_exact_name(self) -> None:
        """Landing does not expand glob metacharacters in bookmark names."""
        _ = run(
            "jj", "bookmark", "create", "one-other", "-r", "main", cwd=self.repository
        )
        unrelated = cli._resolve("one-other", cwd=self.repository)
        self.add_stack_commit("one*")

        self.assertEqual(
            cli.land('bookmarks(exact:"one*")', "main", cwd=self.repository),
            ["one*"],
        )

        self.assertEqual(cli._resolve("one-other", cwd=self.repository), unrelated)

    def test_rejects_a_target_at_the_bookmark(self) -> None:
        """Landing requires the target to differ from the bookmark's commit."""
        with self.assertRaisesRegex(cli.LandError, "already points to"):
            _ = cli.land("main", "main", cwd=self.repository)

    def test_rejects_a_divergent_target(self) -> None:
        """Landing rejects a target outside the bookmark's descendants."""
        self.add_stack_commit("one")
        _ = run("jj", "new", "main", cwd=self.repository)
        _ = run("jj", "describe", "-m", "other", cwd=self.repository)
        _ = run("jj", "bookmark", "create", "other", "-r", "@", cwd=self.repository)

        with self.assertRaisesRegex(cli.LandError, "not a descendant"):
            _ = cli.land("other", "one", cwd=self.repository)

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

        with self.assertRaisesRegex(cli.LandError, "first-parent stack"):
            _ = cli.land("merge", "main", cwd=self.repository)

        self.assertNotEqual(cli._resolve("main", cwd=self.repository), one)
        self.assertEqual(self.bookmark_names(), ["main", "merge", "one", "side"])

    def test_rejects_an_onto_that_is_not_a_local_bookmark(self) -> None:
        """--onto must name a local bookmark, and a rejection changes nothing."""
        self.add_stack_commit("one")
        before = self.bookmark_state()
        self.enterContext(contextlib.chdir(self.repository))

        with contextlib.redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(cli.main(["one", "--onto", "@-"]), 1)

        self.assertIn("not a local bookmark: @-", errors.getvalue())
        self.assertEqual(self.bookmark_state(), before)

    def test_accepts_short_and_long_onto_options(self) -> None:
        """The CLI accepts -o and --onto, and both arguments are optional."""
        parser = cli.create_parser()

        short_options = parser.parse_args(["-o", "release"])
        long_options = parser.parse_args(["feature", "--onto", "release"])
        defaults = parser.parse_args([])

        self.assertEqual(cast(str, short_options.onto), "release")
        self.assertEqual(cast(str, long_options.onto), "release")
        self.assertEqual(cast(str, long_options.revset), "feature")
        self.assertIsNone(cast("str | None", defaults.onto))
        self.assertIsNone(cast("str | None", defaults.revset))

    def test_moves_the_onto_bookmark_instead_of_trunk(self) -> None:
        """--onto selects the bookmark that moves; trunk stays where it was."""
        _ = run("jj", "bookmark", "create", "release", "-r", "main", cwd=self.repository)
        trunk = cli._resolve("main", cwd=self.repository)
        self.add_stack_commit("one")
        tip = cli._resolve("one", cwd=self.repository)
        self.enterContext(contextlib.chdir(self.repository))

        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(cli.main(["one", "--onto", "release"]), 0)

        self.assertEqual(cli._resolve("release", cwd=self.repository), tip)
        self.assertEqual(cli._resolve("main", cwd=self.repository), trunk)
        self.assertEqual(self.bookmark_names(), ["main", "release"])

    def test_lands_the_current_stack_onto_trunk_by_default(self) -> None:
        """Bare land moves the trunk bookmark to the advance target."""
        self.add_origin()
        self.add_stack_commit("feat-a")
        _ = run("jj", "new", cwd=self.repository)
        _ = run("jj", "describe", "-m", "unbookmarked", cwd=self.repository)
        self.add_stack_commit("feat-b")
        tip = cli._resolve("feat-b", cwd=self.repository)
        tip_change = self.short_change_id("feat-b")
        _ = run("jj", "new", cwd=self.repository)
        self.set_advance_target("@-")
        self.enterContext(contextlib.chdir(self.repository))

        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(cli.main([]), 0)

        self.assertEqual(cli._resolve("main", cwd=self.repository), tip)
        self.assertEqual(self.bookmark_names(), ["main"])
        self.assertEqual(
            output.getvalue().splitlines(),
            [f"Moved main to {tip_change}", "Deleted bookmarks: feat-a, feat-b"],
        )

    def test_lands_onto_trunk_again_before_a_push(self) -> None:
        """A local trunk bookmark ahead of its remote is still the default."""
        self.add_origin()
        published = cli._resolve("main@origin", cwd=self.repository)
        self.set_advance_target("@-")
        self.enterContext(contextlib.chdir(self.repository))

        for bookmark in ("one", "two"):
            self.add_stack_commit(bookmark)
            _ = run("jj", "new", cwd=self.repository)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(cli.main([]), 0)
            with self.subTest(bookmark=bookmark):
                self.assertEqual(self.bookmark_names(), ["main"])

        self.assertEqual(
            cli._resolve("main", cwd=self.repository),
            cli._resolve("@-", cwd=self.repository),
        )
        self.assertEqual(cli._resolve("main@origin", cwd=self.repository), published)

    def test_trunk_default_requires_a_local_trunk_bookmark(self) -> None:
        """Without a bookmark on trunk(), land asks for --onto and changes nothing."""
        self.add_stack_commit("one")
        _ = run("jj", "new", cwd=self.repository)
        self.set_advance_target("@-")
        before = self.bookmark_state()
        self.enterContext(contextlib.chdir(self.repository))

        with contextlib.redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(cli.main([]), 1)

        self.assertIn("pass --onto", errors.getvalue())
        self.assertEqual(self.bookmark_state(), before)

    def test_trunk_default_rejects_several_trunk_bookmarks(self) -> None:
        """Several local bookmarks on trunk() make land ask for --onto."""
        _ = run("jj", "bookmark", "create", "master", "-r", "main", cwd=self.repository)
        self.add_origin()
        self.add_stack_commit("one")
        _ = run("jj", "new", cwd=self.repository)
        self.set_advance_target("@-")
        before = self.bookmark_state()
        self.enterContext(contextlib.chdir(self.repository))

        with contextlib.redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(cli.main([]), 1)

        self.assertIn(
            "several local bookmarks match trunk(): main, master; pass --onto",
            errors.getvalue(),
        )
        self.assertEqual(self.bookmark_state(), before)

    def test_defaults_the_target_to_the_bookmark_advance_revset(self) -> None:
        """Without REVSET, the CLI lands jj's configured advance target."""
        self.add_stack_commit("one")
        tip = cli._resolve("one", cwd=self.repository)
        tip_change = self.short_change_id("one")
        _ = run("jj", "new", cwd=self.repository)
        self.set_advance_target("@-")
        self.enterContext(contextlib.chdir(self.repository))

        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(cli.main(["--onto", "main"]), 0)

        self.assertEqual(cli._resolve("main", cwd=self.repository), tip)
        self.assertEqual(self.bookmark_names(), ["main"])
        self.assertIn(f"Moved main to {tip_change}", output.getvalue())

    def test_explicit_target_overrides_the_bookmark_advance_revset(self) -> None:
        """An explicit REVSET wins over jj's configured advance target."""
        for bookmark in ("one", "two"):
            self.add_stack_commit(bookmark)
        first = cli._resolve("one", cwd=self.repository)
        self.enterContext(contextlib.chdir(self.repository))

        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(cli.main(["one", "--onto", "main"]), 0)

        self.assertEqual(cli._resolve("main", cwd=self.repository), first)
        self.assertEqual(self.bookmark_names(), ["main", "two"])


@mock.patch.object(cli, "_resolve_bookmark", return_value="base")
@mock.patch.object(cli, "_resolve", return_value="tip")
@mock.patch.object(cli, "_has_revisions", side_effect=[True, False, False])
@mock.patch.object(cli, "_lines", return_value=['"topic"'])
class AtomicLandTests(unittest.TestCase):
    def test_cleanup_failure_restores_bookmark(
        self,
        _lines: mock.Mock,
        _has_revisions: mock.Mock,
        _resolve: mock.Mock,
        _resolve_bookmark: mock.Mock,
    ) -> None:
        with (
            mock.patch.object(cli, "_run", side_effect=cli.LandError("cleanup failed")),
            mock.patch.object(cli, "_move_bookmark") as move,
            self.assertRaisesRegex(cli.LandError, "restored its original target"),
        ):
            _ = cli.land("topic", "main")
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
            mock.patch.object(cli, "_run", side_effect=cli.LandError("cleanup failed")),
            mock.patch.object(
                cli,
                "_move_bookmark",
                side_effect=[None, cli.LandError("rollback failed")],
            ),
            self.assertRaisesRegex(cli.LandError, "rollback also failed"),
        ):
            _ = cli.land("topic", "main")


if __name__ == "__main__":
    _ = unittest.main()
