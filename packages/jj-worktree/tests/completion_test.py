#!/usr/bin/env python3
# pyright: reportImplicitRelativeImport=false, reportUninitializedInstanceVariable=false

from __future__ import annotations

import os
import pty
import select
import shlex
import subprocess
import sys
import time
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final, override

from support import RepositoryFixture, run


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SOURCE = PROJECT_ROOT / "src"
FISH_COMPLETION = PROJECT_ROOT / "jj-worktree.fish"
ZSH_COMPLETION = PROJECT_ROOT / "_jj-worktree"

def fish_candidates(
    commandline: str, *, cwd: Path, environment: dict[str, str]
) -> set[str]:
    result = run(
        "fish",
        "--no-config",
        "-c",
        "set -g fish_complete_path; source $argv[1]; complete -C $argv[2]",
        str(FISH_COMPLETION),
        commandline,
        cwd=cwd,
        environment=environment,
    )
    return {line.partition("\t")[0] for line in result.stdout.splitlines() if line}


def _wait_for(
    path: Path, master: int, process: subprocess.Popen[bytes], timeout: float = 10
) -> None:
    deadline = time.monotonic() + timeout
    while not path.exists():
        if time.monotonic() >= deadline:
            raise TimeoutError(f"zsh did not create {path}")
        if process.poll() is not None:
            raise RuntimeError(f"zsh exited with status {process.returncode}")
        readable, _, _ = select.select([master], [], [], 0.1)
        if readable:
            _ = os.read(master, 65536)


def _zsh_completion(
    commandline: str,
    index: int,
    *,
    cwd: Path,
    environment: dict[str, str],
) -> tuple[int, str]:
    with TemporaryDirectory() as temporary_directory:
        temporary = Path(temporary_directory)
        ready = temporary / "ready"
        count = temporary / "count"
        result = temporary / "result"
        child_environment = environment.copy()
        child_environment.update(
            {
                "TERM": "dumb",
                "CAPTURE_READY": str(ready),
                "CAPTURE_COUNT": str(count),
                "CAPTURE_RESULT": str(result),
                "CAPTURE_INDEX": str(index),
            }
        )
        master, slave = pty.openpty()
        process = subprocess.Popen(
            ["zsh", "-f"],
            cwd=cwd,
            env=child_environment,
            stdin=slave,
            stdout=slave,
            stderr=slave,
            close_fds=True,
        )
        os.close(slave)
        completion_directory = shlex.quote(str(ZSH_COMPLETION.parent))
        setup = (
            "PS1=; PS2=; autoload -Uz compinit; "
            f"fpath=({completion_directory} $fpath); compinit -D -u; "
            "function _generate_test_completion { _main_complete; "
            "print -r -- $compstate[nmatches] >| $CAPTURE_COUNT; "
            "compstate[insert]=$CAPTURE_INDEX; }; "
            "function _save_test_completion { "
            "print -r -- $BUFFER >| $CAPTURE_RESULT; BUFFER=; zle .accept-line; }; "
            "zle -C test-completion complete-word _generate_test_completion; "
            "zle -N save-test-completion _save_test_completion; "
            "bindkey '^I' test-completion; bindkey '^X' save-test-completion; "
            "print ready >| $CAPTURE_READY\n"
        )
        try:
            _ = os.write(master, setup.encode())
            _wait_for(ready, master, process)
            _ = os.write(master, commandline.encode() + b"\t\x18")
            _wait_for(result, master, process)
            match_count = int(count.read_text().strip())
            completed = result.read_text().removesuffix("\n")
            _ = os.write(master, b"exit\n")
            return match_count, completed
        finally:
            if process.poll() is None:
                process.kill()
            _ = process.wait()
            os.close(master)


def zsh_completed_lines(
    commandline: str, *, cwd: Path, environment: dict[str, str]
) -> set[str]:
    count, first = _zsh_completion(
        commandline, 1, cwd=cwd, environment=environment
    )
    if count == 0:
        return set()
    completed = {first}
    for index in range(2, count + 1):
        _, line = _zsh_completion(
            commandline, index, cwd=cwd, environment=environment
        )
        completed.add(line)
    return completed


@final
class CompletionTests(RepositoryFixture):
    repository_name = "repository"
    environment: dict[str, str]

    @override
    def setUp(self) -> None:
        super().setUp()
        for bookmark in ("local-choice", "managed-choice"):
            _ = run(
                "jj",
                "-R",
                str(self.primary),
                "bookmark",
                "create",
                bookmark,
                "-r",
                "@-",
            )
        binary_directory = self.root / "bin"
        binary_directory.mkdir()
        executable_value = os.environ.get("JJ_WORKTREE_EXECUTABLE")
        executable = binary_directory / "jj-worktree"
        if executable_value is None:
            _ = executable.write_text(
                f"#!{sys.executable}\nimport runpy\nrunpy.run_module('jj_worktree', run_name='__main__')\n"
            )
            executable.chmod(0o755)
        else:
            executable.symlink_to(Path(executable_value).resolve())
        self.environment = os.environ.copy()
        if executable_value is None:
            self.environment["PYTHONPATH"] = os.pathsep.join(
                filter(None, (str(SOURCE), self.environment.get("PYTHONPATH")))
            )
        else:
            _ = self.environment.pop("PYTHONPATH", None)
        self.environment["PATH"] = (
            f"{binary_directory}{os.pathsep}{self.environment['PATH']}"
        )
        _ = run(
            "jj-worktree",
            "add",
            "managed-choice",
            cwd=self.primary,
            environment=self.environment,
        )
        (self.primary / "fixture-path").mkdir()
        _ = run("git", "-C", str(self.primary), "branch", "pending-import")

    def zsh_candidates(self, commandline: str) -> set[str]:
        prefix = commandline.rpartition(" ")[0] + " "
        return {
            line.removeprefix(prefix).removesuffix(" ")
            for line in zsh_completed_lines(
                commandline, cwd=self.primary, environment=self.environment
            )
        }

    def repository_state(self) -> tuple[str, str, str, str]:
        return (
            run(
                "jj",
                "--at-operation=@",
                "--ignore-working-copy",
                "-R",
                str(self.primary),
                "op",
                "log",
                "--no-graph",
                "-n",
                "1",
                "-T",
                'id ++ "\\n"',
            ).stdout,
            run("git", "-C", str(self.primary), "status", "--porcelain=v1").stdout,
            run(
                "git",
                "-C",
                str(self.primary),
                "worktree",
                "list",
                "--porcelain",
            ).stdout,
            run(
                "git",
                "-C",
                str(self.primary),
                "for-each-ref",
                "refs/heads",
                "--format=%(objectname) %(refname)",
            ).stdout,
        )

    def test_fish_completes_commands_options_and_paths(self) -> None:
        self.assertEqual(
            fish_candidates(
                "jj-worktree ", cwd=self.primary, environment=self.environment
            ),
            {"init", "add", "attach", "path", "list", "remove"},
        )
        for command in ("init", "add", "attach", "path", "list", "remove"):
            with self.subTest(command=command):
                options = fish_candidates(
                    f"jj-worktree {command} --",
                    cwd=self.primary,
                    environment=self.environment,
                )
                self.assertIn("--help", options)
        self.assertIn(
            "--revision",
            fish_candidates(
                "jj-worktree add --",
                cwd=self.primary,
                environment=self.environment,
            ),
        )
        self.assertIn(
            "--yes",
            fish_candidates(
                "jj-worktree remove --",
                cwd=self.primary,
                environment=self.environment,
            ),
        )
        self.assertIn(
            "fixture-path/",
            fish_candidates(
                "jj-worktree attach fixture-",
                cwd=self.primary,
                environment=self.environment,
            ),
        )

    def test_zsh_completes_commands_options_and_paths(self) -> None:
        self.assertEqual(
            self.zsh_candidates("jj-worktree "),
            {"init", "add", "attach", "path", "list", "remove"},
        )
        for command in ("init", "add", "attach", "path", "list", "remove"):
            with self.subTest(command=command):
                self.assertIn(
                    "--help", self.zsh_candidates(f"jj-worktree {command} --")
                )
        self.assertIn(
            "--revision", self.zsh_candidates("jj-worktree add --")
        )
        self.assertIn("--yes", self.zsh_candidates("jj-worktree remove --"))
        self.assertIn(
            "fixture-path/", self.zsh_candidates("jj-worktree attach fixture-")
        )

    def test_fish_completes_repository_candidates_without_mutation(self) -> None:
        before = self.repository_state()
        self.assertIn(
            "local-choice",
            fish_candidates(
                "jj-worktree add local-",
                cwd=self.primary,
                environment=self.environment,
            ),
        )
        self.assertNotIn(
            "pending-import",
            fish_candidates(
                "jj-worktree add pending-",
                cwd=self.primary,
                environment=self.environment,
            ),
        )
        for command in ("path", "list", "remove"):
            with self.subTest(command=command):
                self.assertIn(
                    "managed-choice",
                    fish_candidates(
                        f"jj-worktree {command} managed-",
                        cwd=self.primary,
                        environment=self.environment,
                    ),
                )
        self.assertEqual(self.repository_state(), before)

    def test_zsh_completes_repository_candidates_without_mutation(self) -> None:
        before = self.repository_state()
        self.assertIn(
            "local-choice", self.zsh_candidates("jj-worktree add local-")
        )
        self.assertNotIn(
            "pending-import", self.zsh_candidates("jj-worktree add pending-")
        )
        for command in ("path", "list", "remove"):
            with self.subTest(command=command):
                self.assertIn(
                    "managed-choice",
                    self.zsh_candidates(f"jj-worktree {command} managed-"),
                )
        self.assertEqual(self.repository_state(), before)


if __name__ == "__main__":
    _ = unittest.main()
