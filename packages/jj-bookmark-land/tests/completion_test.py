#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path
from typing import final


PROJECT_ROOT = Path(__file__).resolve().parent.parent
FISH_COMPLETION = PROJECT_ROOT / "jj-bookmark-land.fish"
ZSH_COMPLETION = PROJECT_ROOT / "_jj-bookmark-land"


def run(*arguments: str) -> subprocess.CompletedProcess[str]:
    """Run a completion test command from the package root."""
    return subprocess.run(arguments, cwd=PROJECT_ROOT, check=True, capture_output=True, text=True)


@final
class CompletionTests(unittest.TestCase):
    """Verify shell completion definitions and dynamic candidates."""

    def test_fish_completes_options_and_bookmarks(self) -> None:
        """Fish completes options and bookmarks in positional contexts."""
        script = (
            "set -g fish_complete_path; "
            "function jj; printf 'feature\\nmain\\n'; end; "
            "source $argv[1]; complete -C $argv[2]"
        )
        options = run(
            "fish", "--no-config", "-c", script, str(FISH_COMPLETION), "jj-bookmark-land --"
        ).stdout
        into_bookmarks = run(
            "fish", "--no-config", "-c", script, str(FISH_COMPLETION), "jj-bookmark-land --into "
        ).stdout
        bookmarks = run(
            "fish", "--no-config", "-c", script, str(FISH_COMPLETION), "jj-bookmark-land "
        ).stdout
        bookmarks_after_into = run(
            "fish", "--no-config", "-c", script, str(FISH_COMPLETION), "jj-bookmark-land --into main "
        ).stdout
        self.assertIn("--into", {line.partition("\t")[0] for line in options.splitlines()})
        self.assertEqual(
            {"feature", "main"},
            {line.partition("\t")[0] for line in into_bookmarks.splitlines()},
        )
        self.assertEqual(
            {"feature", "main"},
            {line.partition("\t")[0] for line in bookmarks.splitlines()},
        )
        self.assertEqual(
            {"feature", "main"},
            {line.partition("\t")[0] for line in bookmarks_after_into.splitlines()},
        )

    def test_zsh_defines_options_and_bookmark_arguments(self) -> None:
        """Zsh declares options and bookmark-valued arguments."""
        result = run(
            "zsh",
            "-f",
            "-c",
            "function _arguments { print -rl -- $@; }; source $1",
            "completion-test",
            str(ZSH_COMPLETION),
        )
        lines = result.stdout.splitlines()
        self.assertIn("--into[destination bookmark]:bookmark:_jj_bookmark_land_bookmarks", lines)
        self.assertIn("--forget[forget landed bookmarks]", lines)
        self.assertIn("1:stack-tip bookmark:_jj_bookmark_land_bookmarks", lines)


if __name__ == "__main__":
    _ = unittest.main()
