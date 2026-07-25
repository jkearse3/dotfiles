#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path
from typing import final


PROJECT_ROOT = Path(__file__).resolve().parent.parent
FISH_COMPLETION = PROJECT_ROOT / "commit-message.fish"
ZSH_COMPLETION = PROJECT_ROOT / "_commit-message"


def run(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        arguments, cwd=PROJECT_ROOT, check=True, capture_output=True, text=True
    )


def fish_candidates(commandline: str) -> set[str]:
    result = run(
        "fish",
        "--no-config",
        "-c",
        "set -g fish_complete_path; source $argv[1]; complete -C $argv[2]",
        str(FISH_COMPLETION),
        commandline,
    )
    return {line.partition("\t")[0] for line in result.stdout.splitlines() if line}


@final
class CompletionTests(unittest.TestCase):
    def test_fish_completes_subcommands_and_options(self) -> None:
        self.assertEqual(
            {"format", "check"}, fish_candidates("commit-message ")
        )
        self.assertIn(
            "--body-width", fish_candidates("commit-message format --")
        )
        check_options = fish_candidates("commit-message check --")
        self.assertIn("--subject-width", check_options)
        self.assertIn("--body-width", check_options)

    def test_zsh_defines_subcommands_and_options(self) -> None:
        result = run(
            "zsh",
            "-f",
            "-c",
            "function _arguments { print -rl -- $@; }; source $1",
            "completion-test",
            str(ZSH_COMPLETION),
        )
        lines = result.stdout.splitlines()
        subcommands = (
            r"1:command:((format\:format\ a\ commit\ description "
            + r"check\:validate\ a\ commit\ description))"
        )
        self.assertIn(
            subcommands,
            lines,
        )

        for command, expected in (
            ("format", "--body-width[maximum body/footer line width]:characters"),
            ("check", "--subject-width[maximum subject width]:characters"),
        ):
            with self.subTest(command=command):
                command_result = run(
                    "zsh",
                    "-f",
                    "-c",
                    "words=(commit-message $2); function _arguments { print -rl -- $@; }; source $1",
                    "completion-test",
                    str(ZSH_COMPLETION),
                    command,
                )
                self.assertIn(expected, command_result.stdout.splitlines())


if __name__ == "__main__":
    _ = unittest.main()
