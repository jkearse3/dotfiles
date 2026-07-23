#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final


PROJECT_ROOT = Path(__file__).resolve().parent.parent
FISH_COMPLETION = PROJECT_ROOT / "jj-worktree-add.fish"
ZSH_COMPLETION = PROJECT_ROOT / "_jj-worktree-add"


def run(*arguments: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(arguments, cwd=cwd, check=True, capture_output=True, text=True)


@final
class CompletionTests(unittest.TestCase):
    def test_fish_completes_help_and_revisions_without_offering_paths(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "fixture-path").mkdir()
            script = (
                "set -g fish_complete_path; "
                "function jj; "
                "string match -q '*!remote && present*' -- \"$argv\"; and printf 'feature\\nmain\\n'; "
                "end; "
                "source $argv[1]; complete -C $argv[2]"
            )
            options = run(
                "fish",
                "--no-config",
                "-c",
                script,
                str(FISH_COMPLETION),
                "jj-worktree-add --",
                cwd=root,
            ).stdout
            names = run(
                "fish",
                "--no-config",
                "-c",
                script,
                str(FISH_COMPLETION),
                "jj-worktree-add fixture-",
                cwd=root,
            ).stdout
            revisions = run(
                "fish",
                "--no-config",
                "-c",
                script,
                str(FISH_COMPLETION),
                "jj-worktree-add name -r ",
                cwd=root,
            ).stdout
        option_candidates = {line.partition("\t")[0] for line in options.splitlines()}
        name_candidates = {line.partition("\t")[0] for line in names.splitlines()}
        revision_candidates = {line.partition("\t")[0] for line in revisions.splitlines()}
        self.assertIn("--help", option_candidates)
        self.assertNotIn("fixture-path/", name_candidates)
        self.assertEqual(revision_candidates, {"@", "@-", "feature", "main"})

    def test_zsh_defines_help_revision_and_name_arguments(self) -> None:
        script = "function _arguments { print -rl -- $@; }; source $1"
        result = run("zsh", "-f", "-c", script, "completion-test", str(ZSH_COMPLETION), cwd=PROJECT_ROOT)
        self.assertIn("(-h --help)-h[show help]", result.stdout.splitlines())
        self.assertIn(
            "-r[revision revset]:revision revset:_jj_worktree_add_revisions", result.stdout.splitlines()
        )
        self.assertIn("1:worktree name:", result.stdout.splitlines())

    def test_zsh_revision_completion_includes_common_revsets_and_bookmarks(self) -> None:
        script = (
            "function jj { [[ \"$*\" == *'!remote && present'* ]] && print -rl -- feature main; }; "
            "function _describe { print -rl -- ${(@P)2}; }; "
            "function compadd { shift; print -rl -- ${(@P)1}; }; "
            "source $1; _jj_worktree_add_revisions"
        )
        result = run("zsh", "-f", "-c", script, "completion-test", str(ZSH_COMPLETION), cwd=PROJECT_ROOT)
        self.assertEqual(
            set(result.stdout.splitlines()),
            {"@:current revision", "@-:parent revision", "feature", "main"},
        )


if __name__ == "__main__":
    _ = unittest.main()
