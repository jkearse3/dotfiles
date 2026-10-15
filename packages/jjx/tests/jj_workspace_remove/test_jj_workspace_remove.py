#!/usr/bin/env python3

from __future__ import annotations

import os
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final, override

import jjx


PACKAGE_PARENT = Path(jjx.__file__).resolve().parents[1]


def run(
    *arguments: str,
    check: bool = True,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        arguments,
        cwd=cwd,
        check=check,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


@final
class WorkspaceRemoveTests(unittest.TestCase):
    temporary_directory: TemporaryDirectory[str]
    root: Path
    primary: Path
    env: dict[str, str]

    @override
    def setUp(self) -> None:
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name).resolve()
        home = self.root / "home"
        (home / ".config").mkdir(parents=True)
        self.env = os.environ | {
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(home / ".config"),
            "XDG_CACHE_HOME": str(home / ".cache"),
            "XDG_STATE_HOME": str(home / ".state"),
            "GIT_CONFIG_GLOBAL": str(self.root / "gitconfig"),
            "GIT_CONFIG_NOSYSTEM": "1",
            "PYTHONPATH": os.pathsep.join(
                [str(PACKAGE_PARENT), *filter(None, [os.environ.get("PYTHONPATH")])]
            ),
            "JJ_USER": "Test User",
            "JJ_EMAIL": "test@example.com",
        }
        _ = (self.root / "gitconfig").write_text(
            "[user]\n\tname = Test User\n\temail = test@example.com\n"
        )

        self.primary = self.root / "primary"
        _ = run("git", "init", str(self.primary), env=self.env)
        _ = (self.primary / "tracked").write_text("initial\n")
        _ = run("jj", "git", "init", "--colocate", cwd=self.primary, env=self.env)
        _ = run("jj", "commit", "-m", "initial", cwd=self.primary, env=self.env)

    def jjx(self, *arguments: str, cwd: Path | None = None) -> subprocess.CompletedProcess[bytes]:
        return run(
            sys.executable,
            "-m",
            "jjx",
            *arguments,
            check=False,
            cwd=cwd if cwd is not None else self.root,
            env=self.env,
        )

    def add_workspace(self, name: str, *, owner: Path | None = None) -> Path:
        path = self.root / name
        _ = run(
            "jj",
            "workspace",
            "add",
            str(path),
            cwd=owner if owner is not None else self.primary,
            env=self.env,
        )
        return path

    def workspace_names(self, repository: Path | None = None) -> list[str]:
        output = run(
            "jj",
            "workspace",
            "list",
            "-T",
            'name ++ "\\n"',
            cwd=repository if repository is not None else self.primary,
            env=self.env,
        ).stdout
        return sorted(output.decode().splitlines())

    def test_removes_workspace_and_keeps_its_changes(self) -> None:
        workspace = self.add_workspace("feature")
        nested = workspace / "nested"
        nested.mkdir()
        _ = (nested / "edited").write_text("unsaved\n")

        result = self.jjx("workspace", "remove", str(nested))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout, f"removed jj workspace feature at {workspace}\n".encode()
        )
        self.assertFalse(workspace.exists())
        self.assertEqual(self.workspace_names(), ["default"])
        worktrees = run("git", "-C", str(self.primary), "worktree", "list", env=self.env)
        self.assertNotIn(os.fsencode(workspace), worktrees.stdout)
        edited = run(
            "jj", "log", "-r", 'files("nested/edited")', "--no-graph", "-T", "change_id",
            cwd=self.primary, env=self.env,
        )
        self.assertNotEqual(edited.stdout, b"")

    def test_removes_current_directory_workspace(self) -> None:
        workspace = self.add_workspace("feature")
        result = self.jjx("workspace", "remove", cwd=workspace)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(workspace.exists())

    def test_dry_run_reports_without_removing(self) -> None:
        workspace = self.add_workspace("feature")
        result = self.jjx("workspace", "remove", "--dry-run", str(workspace))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout, f"would remove jj workspace feature at {workspace}\n".encode()
        )
        self.assertTrue(workspace.is_dir())
        self.assertEqual(self.workspace_names(), ["default", "feature"])

    def test_removes_workspace_owned_by_linked_worktree(self) -> None:
        linked = self.root / "linked"
        _ = run("git", "-C", str(self.primary), "worktree", "add", "--detach", str(linked), env=self.env)
        _ = self.jjx("ensure", str(linked))
        workspace = self.add_workspace("feature", owner=linked)

        result = self.jjx("workspace", "remove", str(workspace))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(workspace.exists())
        self.assertEqual(self.workspace_names(linked), ["default"])

    def test_refuses_checkouts_not_created_by_jj_workspace_add(self) -> None:
        linked = self.root / "linked"
        _ = run("git", "-C", str(self.primary), "worktree", "add", "--detach", str(linked), env=self.env)
        _ = self.jjx("ensure", str(linked))
        plain = self.root / "plain"
        plain.mkdir()
        for path, message in (
            (self.primary, b"is not a workspace created by jj workspace add"),
            (linked, b"is not a workspace created by jj workspace add"),
            (plain, b"error:"),
        ):
            with self.subTest(path=path):
                result = self.jjx("workspace", "remove", str(path))
                self.assertEqual(result.returncode, 1)
                self.assertIn(message, result.stderr)
        self.assertTrue((self.primary / ".jj").is_dir())
        self.assertTrue((linked / ".jj").is_dir())


if __name__ == "__main__":
    _ = unittest.main()
