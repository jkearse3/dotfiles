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
FOLLOW_UP_STUB = """#!/bin/sh
printf '%s %s\\n' "$(basename "$0")" "$*" >>"$FOLLOW_UP_LOG"
echo "stdout from $(basename "$0")"
case " $FAILING_FOLLOW_UPS " in
  *" $(basename "$0") "*) echo "failure from $(basename "$0")" >&2; exit 3 ;;
esac
"""


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
class WorkspaceAddTests(unittest.TestCase):
    temporary_directory: TemporaryDirectory[str]
    root: Path
    primary: Path
    follow_up_log: Path
    env: dict[str, str]

    @override
    def setUp(self) -> None:
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name).resolve()
        home = self.root / "home"
        (home / ".config").mkdir(parents=True)
        stubs = self.root / "stubs"
        stubs.mkdir()
        for name in ("worktree-include", "direnv-worktree"):
            stub = stubs / name
            _ = stub.write_text(FOLLOW_UP_STUB)
            stub.chmod(0o755)
        self.follow_up_log = self.root / "follow-ups.log"
        self.env = os.environ | {
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(home / ".config"),
            "XDG_CACHE_HOME": str(home / ".cache"),
            "XDG_STATE_HOME": str(home / ".state"),
            "PATH": f"{stubs}{os.pathsep}{os.environ['PATH']}",
            "PYTHONPATH": os.pathsep.join(
                [str(PACKAGE_PARENT), *filter(None, [os.environ.get("PYTHONPATH")])]
            ),
            "FOLLOW_UP_LOG": str(self.follow_up_log),
            "FAILING_FOLLOW_UPS": "",
            "JJ_USER": "Test User",
            "JJ_EMAIL": "test@example.com",
        }

        self.primary = self.root / "primary"
        _ = run("git", "init", str(self.primary), env=self.env)
        _ = (self.primary / "tracked").write_text("initial\n")
        _ = run("jj", "git", "init", "--colocate", cwd=self.primary, env=self.env)
        _ = run("jj", "commit", "-m", "initial", cwd=self.primary, env=self.env)

    def workspace_add(self, *arguments: str) -> subprocess.CompletedProcess[bytes]:
        return run(
            sys.executable,
            "-m",
            "jjx",
            "workspace",
            "add",
            *arguments,
            check=False,
            cwd=self.primary,
            env=self.env,
        )

    def follow_ups(self) -> list[str]:
        if not self.follow_up_log.exists():
            return []
        return self.follow_up_log.read_text().splitlines()

    def workspace_names(self) -> list[str]:
        output = run(
            "jj", "workspace", "list", "-T", 'name ++ "\\n"', cwd=self.primary, env=self.env
        ).stdout
        return sorted(output.decode().splitlines())

    def test_prepares_new_workspace_and_prints_only_its_root(self) -> None:
        workspace = self.root / "feature"
        result = self.workspace_add(str(workspace))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, os.fsencode(workspace) + b"\n")
        self.assertEqual(
            self.follow_ups(),
            [f"worktree-include --prepare {workspace}", f"direnv-worktree prepare {workspace}"],
        )
        self.assertIn(b"stdout from worktree-include", result.stderr)
        top_level = run("git", "-C", str(workspace), "rev-parse", "--show-toplevel", env=self.env)
        self.assertEqual(top_level.stdout, os.fsencode(workspace) + b"\n")

    def test_passes_arguments_to_jj_workspace_add(self) -> None:
        workspace = self.root / "destination"
        result = self.workspace_add("--name", "custom", "-m", "started", str(workspace))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.workspace_names(), ["custom", "default"])
        description = run(
            "jj", "log", "-r", "custom@", "--no-graph", "-T", "description",
            cwd=self.primary, env=self.env,
        ).stdout
        self.assertEqual(description, b"started\n")

    def test_failed_preparation_runs_every_step_and_keeps_workspace(self) -> None:
        self.env["FAILING_FOLLOW_UPS"] = "worktree-include"
        workspace = self.root / "feature"
        result = self.workspace_add(str(workspace))
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(len(self.follow_ups()), 2)
        self.assertIn(b"failure from worktree-include", result.stderr)
        self.assertIn(f"rerun: worktree-include --prepare {workspace}\n".encode(), result.stderr)
        self.assertNotIn(b"rerun: direnv-worktree", result.stderr)
        self.assertEqual(self.workspace_names(), ["default", "feature"])

    def test_skips_preparation_without_git_worktree(self) -> None:
        workspace = self.root / "plain"
        result = self.workspace_add("--no-colocate", str(workspace))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, os.fsencode(workspace) + b"\n")
        self.assertIn(b"no Git worktree of its own; skipped preparation", result.stderr)
        self.assertEqual(self.follow_ups(), [])

    def test_jj_failure_skips_preparation(self) -> None:
        existing = self.root / "occupied"
        existing.mkdir()
        _ = (existing / "file").write_text("occupied\n")
        result = self.workspace_add(str(existing))
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"jj workspace add failed", result.stderr)
        self.assertEqual(self.follow_ups(), [])
        self.assertEqual(self.workspace_names(), ["default"])

    def test_rejects_repository_option_and_prints_help_without_creating(self) -> None:
        for arguments, stream, expected in (
            (("-R", str(self.primary), "x"), "stderr", b"-R/--repository is not supported"),
            ((f"--repository={self.primary}", "x"), "stderr", b"-R/--repository is not supported"),
            (("x", "--help"), "stdout", b"usage: jjx workspace add"),
        ):
            with self.subTest(arguments=arguments):
                result = self.workspace_add(*arguments)
                output = result.stdout if stream == "stdout" else result.stderr
                self.assertIn(expected, output)
                self.assertEqual(self.workspace_names(), ["default"])
        self.assertEqual(self.follow_ups(), [])


if __name__ == "__main__":
    _ = unittest.main()
