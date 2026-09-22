#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path
from typing import final


PROJECT_ROOT = Path(__file__).resolve().parent.parent
FISH_COMPLETION = PROJECT_ROOT / "jj-bookmark-backup.fish"
ZSH_COMPLETION = PROJECT_ROOT / "_jj-bookmark-backup"


def run(*arguments: str) -> subprocess.CompletedProcess[str]:
    """Run a completion test command from the package root."""
    return subprocess.run(arguments, cwd=PROJECT_ROOT, check=True, capture_output=True, text=True)


@final
class CompletionTests(unittest.TestCase):
    """Verify shell completion definitions and dynamic candidates."""

    def test_fish_completes_options_bookmarks_and_remotes(self) -> None:
        """Fish offers bookmark and remote candidates in their argument positions."""
        script = (
            "set -g fish_complete_path; "
            "function jj; "
            "if contains -- bookmark $argv; printf 'feature/api\\nmain\\n'; "
            "else; printf 'origin url\\nupstream url\\n'; end; end; "
            "source $argv[1]; complete -C $argv[2]"
        )
        options = run(
            "fish", "--no-config", "-c", script, str(FISH_COMPLETION), "jj-bookmark-backup --"
        ).stdout
        bookmarks = run(
            "fish", "--no-config", "-c", script, str(FISH_COMPLETION), "jj-bookmark-backup "
        ).stdout
        after_bookmark = run(
            "fish",
            "--no-config",
            "-c",
            script,
            str(FISH_COMPLETION),
            "jj-bookmark-backup main ",
        ).stdout
        remotes = run(
            "fish",
            "--no-config",
            "-c",
            script,
            str(FISH_COMPLETION),
            "jj-bookmark-backup --remote ",
        ).stdout

        option_names = {line.partition("\t")[0] for line in options.splitlines()}
        self.assertIn("--remote", option_names)
        self.assertEqual(
            {"feature/api", "main"},
            {
                line.partition("\t")[0]
                for line in bookmarks.splitlines()
                if not line.startswith("-")
            },
        )
        self.assertEqual(after_bookmark, "")
        self.assertEqual(
            {"origin", "upstream"},
            {line.partition("\t")[0] for line in remotes.splitlines()},
        )

    def test_zsh_defines_bookmark_and_remote_arguments(self) -> None:
        """Zsh declares dynamic completion for both command arguments."""
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
            "--remote[source remote]:remote:_jj_bookmark_backup_remotes",
            lines,
        )
        self.assertIn("1:bookmark:_jj_bookmark_backup_bookmarks", lines)


if __name__ == "__main__":
    _ = unittest.main()
