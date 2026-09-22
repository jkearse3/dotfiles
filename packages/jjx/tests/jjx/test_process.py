from __future__ import annotations

import errno
import subprocess
import unittest
from pathlib import Path
from typing import final
from unittest.mock import patch

from jjx.commands import process


class ExampleCommandError(Exception):
    """Test-only user-facing command failure."""


@final
class ProcessTests(unittest.TestCase):
    """Verify shared process launch and failure translation."""

    def test_capture_translates_process_launch_failures(self) -> None:
        missing = FileNotFoundError(errno.ENOENT, "not found", "missing")
        with (
            patch("subprocess.run", side_effect=missing),
            self.assertRaisesRegex(ExampleCommandError, "could not run missing"),
        ):
            _ = process.capture_bytes(["missing"], error_type=ExampleCommandError)

    def test_checked_bytes_includes_quoted_command_and_stderr(self) -> None:
        result = subprocess.CompletedProcess([], 2, b"", b"bad option\n")
        with (
            patch("subprocess.run", return_value=result),
            self.assertRaisesRegex(
                ExampleCommandError,
                r"tool 'two words' failed: bad option",
            ),
        ):
            _ = process.checked_bytes(
                ["tool", "two words"],
                error_type=ExampleCommandError,
                cwd=Path("/unused"),
            )

    def test_run_status_preserves_child_exit_status(self) -> None:
        result = subprocess.CompletedProcess[bytes]([], 23)
        with patch("subprocess.run", return_value=result):
            self.assertEqual(
                23,
                process.run_status(["tool"], error_type=ExampleCommandError),
            )
