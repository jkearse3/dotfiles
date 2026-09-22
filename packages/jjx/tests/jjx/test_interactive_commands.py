from __future__ import annotations

import io
import subprocess
import unittest
from contextlib import redirect_stderr
from typing import final
from unittest.mock import patch

from jjx.commands import interactive


@final
class InteractiveCommandTests(unittest.TestCase):
    """Verify cancellation, failure, and launch-error status contracts."""

    def test_single_selectors_treat_only_fzf_cancellation_as_success(self) -> None:
        listed = subprocess.CompletedProcess([], 0, "candidate\tdescription\n", "")
        for selector in (interactive.bookmark_select, interactive.change_select):
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
