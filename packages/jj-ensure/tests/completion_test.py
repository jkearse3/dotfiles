#!/usr/bin/env python3
# pyright: reportUninitializedInstanceVariable=false

from __future__ import annotations

import os
import pty
import select
import shlex
import subprocess
import time
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final, override


PROJECT_ROOT = Path(__file__).resolve().parent.parent
FISH_COMPLETION = PROJECT_ROOT / "jj-ensure.fish"
ZSH_COMPLETION = PROJECT_ROOT / "_jj-ensure"


def run(*arguments: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(arguments, cwd=cwd, check=True, capture_output=True, text=True)


def fish_candidates(commandline: str, *, cwd: Path) -> set[str]:
    result = run(
        "fish",
        "--no-config",
        "-c",
        "set -g fish_complete_path; source $argv[1]; complete -C $argv[2]",
        str(FISH_COMPLETION),
        commandline,
        cwd=cwd,
    )
    return {line.partition("\t")[0] for line in result.stdout.splitlines() if line}


def wait_for(path: Path, master: int, process: subprocess.Popen[bytes]) -> None:
    deadline = time.monotonic() + 10
    while not path.exists():
        if time.monotonic() >= deadline:
            raise TimeoutError(f"zsh did not create {path}")
        if process.poll() is not None:
            raise RuntimeError(f"zsh exited with status {process.returncode}")
        readable, _, _ = select.select([master], [], [], 0.1)
        if readable:
            _ = os.read(master, 65536)


def zsh_candidates(commandline: str, *, cwd: Path) -> set[str]:
    candidates: set[str] = set()
    count, completed = zsh_completion(commandline, 1, cwd=cwd)
    if count == 0:
        return candidates
    prefix = commandline.rpartition(" ")[0] + " "
    candidates.add(completed.removeprefix(prefix).removesuffix(" "))
    for index in range(2, count + 1):
        _, completed = zsh_completion(commandline, index, cwd=cwd)
        candidates.add(completed.removeprefix(prefix).removesuffix(" "))
    return candidates


def zsh_completion(commandline: str, index: int, *, cwd: Path) -> tuple[int, str]:
    with TemporaryDirectory() as temporary_directory:
        temporary = Path(temporary_directory)
        ready = temporary / "ready"
        count = temporary / "count"
        result = temporary / "result"
        environment = os.environ.copy()
        environment.update(
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
            env=environment,
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
            wait_for(ready, master, process)
            _ = os.write(master, commandline.encode() + b"\t\x18")
            wait_for(result, master, process)
            match_count = int(count.read_text().strip())
            completed = result.read_text().removesuffix("\n")
            _ = os.write(master, b"exit\n")
            return match_count, completed
        finally:
            if process.poll() is None:
                process.kill()
            _ = process.wait()
            os.close(master)


@final
class CompletionTests(unittest.TestCase):
    temporary_directory: TemporaryDirectory[str]
    root: Path

    @override
    def setUp(self) -> None:
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        (self.root / "fixture-path").mkdir()

    def test_fish_completes_options_and_directories(self) -> None:
        options = fish_candidates("jj-ensure --", cwd=self.root)
        self.assertIn("--help", options)
        self.assertIn("--dry-run", options)
        self.assertIn("fixture-path/", fish_candidates("jj-ensure fixture-", cwd=self.root))
        self.assertIn("fixture-path/", fish_candidates("jj-ensure --dry-run fixture-", cwd=self.root))

    def test_zsh_completes_options_and_directories(self) -> None:
        options = zsh_candidates("jj-ensure --", cwd=self.root)
        self.assertIn("--help", options)
        self.assertIn("--dry-run", options)
        self.assertIn("fixture-path/", zsh_candidates("jj-ensure fixture-", cwd=self.root))
        self.assertIn("fixture-path/", zsh_candidates("jj-ensure --dry-run fixture-", cwd=self.root))


if __name__ == "__main__":
    _ = unittest.main()
