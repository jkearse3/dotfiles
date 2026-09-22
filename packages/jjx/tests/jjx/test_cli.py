from __future__ import annotations

import io
import unittest
from contextlib import redirect_stderr, redirect_stdout
from collections.abc import Sequence
from typing import final
from unittest.mock import patch

from jjx import cli


@final
class CliTests(unittest.TestCase):
    """Verify command discovery and direct Python dispatch."""

    def test_root_help_lists_command_groups(self) -> None:
        output = io.StringIO()
        with redirect_stdout(output):
            status = cli.main(["--help"])
        self.assertEqual(0, status)
        self.assertIn("bookmark", output.getvalue())
        self.assertIn("worktree", output.getvalue())

    def test_group_help_lists_leaf_commands(self) -> None:
        output = io.StringIO()
        with redirect_stdout(output):
            status = cli.main(["bookmark", "--help"])
        self.assertEqual(0, status)
        self.assertIn("backup", output.getvalue())
        self.assertIn("stacked", output.getvalue())

    def test_leaf_dispatches_directly_to_python_handler(self) -> None:
        captured: list[tuple[list[str], str]] = []

        def fake_main(arguments: Sequence[str], *, prog: str) -> int:
            captured.append((list(arguments), prog))
            return 7

        replacement = cli.Command.define(
            "description format",
            "test",
            fake_main,
        )
        commands = tuple(
            replacement if item.path == replacement.path else item
            for item in cli.COMMANDS
        )
        with patch.object(cli, "COMMANDS", commands):
            status = cli.main(["description", "format", "--dry-run"])

        self.assertEqual(7, status)
        self.assertEqual([(["--dry-run"], "jjx description format")], captured)

    def test_unknown_command_is_a_usage_error(self) -> None:
        errors = io.StringIO()
        with redirect_stderr(errors):
            status = cli.main(["bookmark", "missing"])
        self.assertEqual(2, status)
        self.assertIn("unknown command", errors.getvalue())
