from __future__ import annotations

import io
import subprocess
import unittest
from contextlib import redirect_stderr, redirect_stdout
from typing import final
from unittest.mock import patch

from jjx.commands import interactive


@final
class InteractiveCommandTests(unittest.TestCase):
    """Verify cancellation, failure, and launch-error status contracts."""

    def test_single_selectors_treat_only_fzf_cancellation_as_success(self) -> None:
        candidates = subprocess.CompletedProcess([], 0, "candidate\tdescription\n", "")
        worktrees = subprocess.CompletedProcess([], 0, "worktree /repo\0HEAD abc\0\0", "")
        for selector, listed in (
            (interactive.bookmark_select, candidates),
            (interactive.change_select, candidates),
            (interactive.worktree_select, worktrees),
        ):
            with self.subTest(selector=selector.__name__):
                cancelled = subprocess.CompletedProcess([], 130, "", "")
                with patch.object(interactive, "_run", side_effect=[listed, cancelled]):
                    self.assertEqual(0, selector([], prog=f"jjx {selector.__name__}"))

                failed = subprocess.CompletedProcess([], 23, "", "")
                with patch.object(interactive, "_run", side_effect=[listed, failed]):
                    self.assertEqual(23, selector([], prog=f"jjx {selector.__name__}"))

    def test_launch_failure_becomes_a_concise_integer_status(self) -> None:
        error = io.StringIO()
        failure = interactive.InteractiveCommandError("could not run fzf: missing")
        with patch.object(interactive, "_run", side_effect=failure), redirect_stderr(error):
            status = interactive.bookmark_select([], prog="jjx bookmark select")
        self.assertEqual(1, status)
        self.assertEqual(
            "jjx bookmark select: could not run fzf: missing\n",
            error.getvalue(),
        )

    def test_worktree_select_offers_each_worktree_path_to_fzf(self) -> None:
        listed = subprocess.CompletedProcess(
            [],
            0,
            "worktree /repo\0HEAD abc\0branch refs/heads/main\0\0"
            "worktree /repo/.jj-worktrees/with space\0HEAD def\0detached\0\0",
            "",
        )
        picked = subprocess.CompletedProcess([], 0, "/repo/.jj-worktrees/with space\n", "")
        output = io.StringIO()
        with (
            patch.object(interactive, "_run", side_effect=[listed, picked]) as run,
            redirect_stdout(output),
        ):
            status = interactive.worktree_select([], prog="jjx worktree select")

        self.assertEqual(0, status)
        self.assertEqual(
            "/repo\0/repo/.jj-worktrees/with space\0",
            run.call_args_list[1].kwargs["stdin"],
        )
        self.assertEqual("/repo/.jj-worktrees/with space\n", output.getvalue())

    def test_worktree_select_reports_listing_failure(self) -> None:
        failed = subprocess.CompletedProcess([], 128, "", "")
        error = io.StringIO()
        with patch.object(interactive, "_run", return_value=failed), redirect_stderr(error):
            status = interactive.worktree_select([], prog="jjx worktree select")

        self.assertEqual(1, status)
        self.assertEqual("jjx worktree select: failed to list worktrees\n", error.getvalue())
