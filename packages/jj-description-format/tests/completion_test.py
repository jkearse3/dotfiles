#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path
from typing import final


PROJECT_ROOT = Path(__file__).resolve().parent.parent
FISH_COMPLETION = PROJECT_ROOT / "jj-description-format.fish"
ZSH_COMPLETION = PROJECT_ROOT / "_jj-description-format"


def run(*arguments: str) -> subprocess.CompletedProcess[str]:
    """Run a completion test command from the package root."""
    return subprocess.run(arguments, cwd=PROJECT_ROOT, check=True, capture_output=True, text=True)


@final
class CompletionTests(unittest.TestCase):
    """Verify shell completion definitions and dynamic candidates."""

    def test_fish_completes_options_and_revision_bookmarks(self) -> None:
        """Fish completes options and bookmark candidates for --revision."""
        script = (
            "set -g fish_complete_path; "
            "function jj; printf 'feature\\nmain\\n'; end; "
            "source $argv[1]; complete -C $argv[2]"
        )
        options = run(
            "fish", "--no-config", "-c", script, str(FISH_COMPLETION), "jj-description-format --"
        ).stdout
        revisions = run(
            "fish", "--no-config", "-c", script, str(FISH_COMPLETION), "jj-description-format -r "
        ).stdout
        option_names = {line.partition("\t")[0] for line in options.splitlines()}
        self.assertIn("--revision", option_names)
        self.assertIn("--dry-run", option_names)
        self.assertIn("--subject-width", option_names)
        self.assertIn("--body-width", option_names)
        self.assertEqual(
            {"feature", "main"},
            {line.partition("\t")[0] for line in revisions.splitlines()},
        )

    def test_zsh_defines_options_and_revision_argument(self) -> None:
        """Zsh declares options and the bookmark-valued revision argument."""
        result = run(
            "zsh",
            "-f",
            "-c",
            "function _arguments { print -rl -- $@; }; source $1",
            "completion-test",
            str(ZSH_COMPLETION),
        )
        lines = result.stdout.splitlines()
        self.assertIn(
            "(-r --revision)--revision[target revision]:revision:_jj_description_format_bookmarks",
            lines,
        )
        self.assertIn("--dry-run[show the diff without writing]", lines)
        self.assertIn("--subject-width[maximum subject width]:width:", lines)
        self.assertIn("--body-width[maximum body line width]:width:", lines)


if __name__ == "__main__":
    _ = unittest.main()
