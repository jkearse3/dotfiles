from __future__ import annotations

import subprocess
import unittest
from pathlib import Path
from typing import final

from jjx.cli import COMMANDS

PROJECT_ROOT = Path(__file__).resolve().parents[2]


def fish_completion_descriptions(commandline: str) -> dict[str, str]:
    """Return Fish completion candidates mapped to their descriptions."""
    result = subprocess.run(
        [
            "fish",
            "--no-config",
            "-c",
            "for file in $argv[1]/*.fish; source $file; end; complete -C $argv[2]",
            str(PROJECT_ROOT / "completions"),
            commandline,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    completions: dict[str, str] = {}
    for line in result.stdout.splitlines():
        candidate, separator, description = line.partition("\t")
        if candidate:
            completions[candidate] = description if separator else ""
    return completions


def fish_candidates(commandline: str) -> set[str]:
    """Return Fish completion candidates for COMMANDLINE."""
    return set(fish_completion_descriptions(commandline))


@final
class CompletionTests(unittest.TestCase):
    """Verify discovery of the hierarchical jjx command names."""

    def test_root_completes_described_groups(self) -> None:
        descriptions = fish_completion_descriptions("jjx ")
        expected = {
            "bookmark": "Commands for bookmarks",
            "change": "Commands for changes",
            "description": "Commands for descriptions",
            "ensure": "Ensure a Git checkout has compatible jj state",
            "worktree": "Commands for Git worktrees",
        }

        self.assertEqual(expected, {name: descriptions[name] for name in expected})

        root_options = fish_completion_descriptions("jjx --")
        self.assertTrue(root_options["--help"])

    def test_every_fish_command_has_its_cli_description(self) -> None:
        for command in COMMANDS:
            parent = " ".join(command.path[:-1])
            commandline = f"jjx {parent} " if parent else "jjx "
            descriptions = fish_completion_descriptions(commandline)
            with self.subTest(command=command.prog):
                self.assertEqual(command.description, descriptions[command.path[-1]])

    def test_bookmark_completes_leaf_commands(self) -> None:
        candidates = fish_candidates("jjx bookmark ")

        self.assertEqual(
            {
                "backup",
                "current",
                "default",
                "land",
                "nearest",
                "previous",
                "push",
                "rebase",
                "select",
                "stacked",
            },
            candidates,
        )

    def test_leaf_arguments_do_not_repeat_command_names(self) -> None:
        candidates = fish_candidates("jjx bookmark land ")

        self.assertFalse({"backup", "land", "stacked"} & candidates)

    def test_every_fish_leaf_declares_its_options(self) -> None:
        expected_options = {
            "bookmark backup": {"--help", "--remote"},
            "bookmark current": {"--help"},
            "bookmark default": {"--help"},
            "bookmark land": {"--destination", "--dry-run", "--forget", "--help"},
            "bookmark nearest": {"--help"},
            "bookmark previous": {"--help"},
            "bookmark push": {
                "--allow-conflicts", "--allow-empty-description", "--allow-private",
                "--at-op", "--at-operation", "--color", "--config", "--config-file",
                "--debug", "--dry-run", "--help", "--ignore-immutable",
                "--ignore-working-copy", "--no-integrate-operation", "--no-pager",
                "--option", "--quiet", "--remote", "--repository",
            },
            "bookmark rebase": {"--help"},
            "bookmark select": {"--help"},
            "bookmark stacked": {"--help"},
            "change select": {"--help"},
            "description format": {
                "--body-width", "--dry-run", "--help", "--revision", "--subject-width",
            },
            "ensure": {"--dry-run", "--help"},
            "worktree add": {"--help"},
        }
        for leaf, expected in expected_options.items():
            with self.subTest(leaf=leaf):
                completions = fish_completion_descriptions(f"jjx {leaf} -")
                self.assertTrue(expected <= completions.keys())
                options = {
                    candidate: description
                    for candidate, description in completions.items()
                    if candidate.startswith("-")
                }
                self.assertTrue(
                    all(options.values()),
                    f"missing option description for jjx {leaf}",
                )

        push_candidates = fish_candidates("jjx bookmark push --")
        selectors = {
            "--all", "--bookmark", "--change", "--deleted", "--named",
            "--revision", "--tag", "--tracked",
        }
        self.assertFalse(selectors & push_candidates)

    def test_fish_stops_completing_consumed_positionals(self) -> None:
        self.assertNotIn("@", fish_candidates("jjx bookmark nearest @ "))
        self.assertNotIn("@", fish_candidates("jjx bookmark rebase main "))
        self.assertNotIn("package.nix", fish_candidates("jjx ensure . "))

    def test_every_zsh_subcommand_has_its_cli_description(self) -> None:
        grouped_commands = {command.path[0] for command in COMMANDS if len(command.path) > 1}
        for group in grouped_commands:
            script = (
                "function _arguments { :; }; function _describe { :; }; "
                "function _values { print -rl -- $@; }; "
                "typeset -a words; words=(jjx $2 ''); CURRENT=3; source $1"
            )
            result = subprocess.run(
                [
                    "zsh",
                    "-f",
                    "-c",
                    script,
                    "completion-test",
                    str(PROJECT_ROOT / "completions" / "_jjx"),
                    group,
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            values = set(result.stdout.splitlines())
            expected = {
                f"{command.path[-1]}[{command.description}]"
                for command in COMMANDS
                if command.path[0] == group
            }
            with self.subTest(group=group):
                self.assertTrue(expected <= values)


    def test_zsh_leaf_declares_options(self) -> None:
        script = (
            "function _arguments { print -rl -- $@; }; "
            "function _describe {}; function _values {}; "
            "typeset -a words; words=(jjx bookmark land --); CURRENT=4; source $1"
        )
        result = subprocess.run(
            [
                "zsh",
                "-f",
                "-c",
                script,
                "completion-test",
                str(PROJECT_ROOT / "completions" / "_jjx"),
            ],
            check=True,
            capture_output=True,
            text=True,
        )

        lines = result.stdout.splitlines()
        self.assertIn("--forget[forget landed bookmarks]", lines)
        self.assertIn("--dry-run[show the landing plan]", lines)
        self.assertTrue(any("--destination" in line for line in lines))

    def test_leaf_completes_options(self) -> None:
        candidates = fish_candidates("jjx bookmark land --")

        self.assertTrue(
            {"--destination", "--dry-run", "--forget", "--help"} <= candidates
        )
