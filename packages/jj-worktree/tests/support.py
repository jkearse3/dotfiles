from __future__ import annotations

# pyright: reportUninitializedInstanceVariable=false

import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import override

from jj_worktree.commands import add
from jj_worktree.core import repository


def run(
    *arguments: str,
    cwd: Path | None = None,
    check: bool = True,
    environment: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(arguments),
        cwd=cwd,
        env=environment,
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


class RepositoryFixture(unittest.TestCase):
    temporary_directory: TemporaryDirectory[str]
    root: Path
    primary: Path
    managed_root: Path

    repository_name: str = "repository with spaces"

    @override
    def setUp(self) -> None:
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name).resolve()
        self.primary = self.root / self.repository_name
        self.primary.mkdir()
        _ = run("git", "init", str(self.primary))
        _ = run("git", "-C", str(self.primary), "config", "user.name", "Test User")
        _ = run(
            "git",
            "-C",
            str(self.primary),
            "config",
            "user.email",
            "test@example.com",
        )
        _ = (self.primary / "tracked").write_text("initial\n")
        _ = run("git", "-C", str(self.primary), "add", "tracked")
        _ = run("git", "-C", str(self.primary), "commit", "-m", "initial")
        _ = run("jj", "git", "init", "--colocate", str(self.primary))
        self.managed_root = self.primary / repository.MANAGED_ROOT_NAME

    def exclude(self) -> Path:
        return self.primary / ".git" / "info" / "exclude"

    def create_bookmark(self, name: str, revision: str = "@-") -> None:
        _ = run("jj", "-R", str(self.primary), "bookmark", "create", name, "-r", revision)

    def create_linked(self, name: str, revision: str = "@-") -> Path:
        self.create_bookmark(name, revision)
        return add.add_worktree(name, start=self.primary)

    def worktree_paths(self) -> list[Path]:
        output = run(
            "git", "-C", str(self.primary), "worktree", "list", "--porcelain"
        ).stdout
        return [
            Path(line.removeprefix("worktree "))
            for line in output.splitlines()
            if line.startswith("worktree ")
        ]
