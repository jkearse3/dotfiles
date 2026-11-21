#!/usr/bin/env python3

from __future__ import annotations

import os
import shlex
import shutil
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final, override

import jjx
from jjx.commands import workspace_add


PACKAGE_PARENT = Path(jjx.__file__).resolve().parents[1]
FOLLOW_UP_STUB = """#!/bin/sh
printf '%s %s\\n' "$(basename "$0")" "$*" >>"$FOLLOW_UP_LOG"
echo "stdout from $(basename "$0")"
case " $FAILING_FOLLOW_UPS " in
  *" $(basename "$0") "*) echo "failure from $(basename "$0")" >&2; exit 3 ;;
esac
"""

NON_COLOCATING_JJ_STUB = """#!/bin/sh
# Stand in for a jj that ignores the --colocate jjx passes when adding a workspace.
if [ "$1 $2 $3" = "workspace add --colocate" ]; then
  shift 3
  exec {jj} workspace add --no-colocate "$@"
fi
exec {jj} "$@"
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

    def workspace_add(
        self, *arguments: str, cwd: Path | None = None
    ) -> subprocess.CompletedProcess[bytes]:
        return run(
            sys.executable,
            "-m",
            "jjx",
            "workspace",
            "add",
            *arguments,
            check=False,
            cwd=self.primary if cwd is None else cwd,
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

    def test_colocates_when_git_colocate_is_disabled(self) -> None:
        jj_config = self.root / "home" / ".config" / "jj" / "config.toml"
        jj_config.parent.mkdir(parents=True)
        _ = jj_config.write_text("[git]\ncolocate = false\n")
        workspace = self.root / "feature"
        result = self.workspace_add(str(workspace))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((workspace / ".git").exists())
        top_level = run("git", "-C", str(workspace), "rev-parse", "--show-toplevel", env=self.env)
        self.assertEqual(top_level.stdout, os.fsencode(workspace) + b"\n")
        self.assertEqual(len(self.follow_ups()), 2)

    def test_fails_without_git_worktree_and_keeps_workspace(self) -> None:
        real_jj = shutil.which("jj", path=self.env["PATH"])
        assert real_jj is not None
        stubs = self.root / "non-colocating-stubs"
        stubs.mkdir()
        stub = stubs / "jj"
        _ = stub.write_text(NON_COLOCATING_JJ_STUB.format(jj=shlex.quote(real_jj)))
        stub.chmod(0o755)
        self.env["PATH"] = f"{stubs}{os.pathsep}{self.env['PATH']}"

        result = self.workspace_add("--name", "feature", str(self.root / "feature"))
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"has no Git worktree of its own", result.stderr)
        self.assertIn(b"remove it with: jj workspace remove feature", result.stderr)
        self.assertEqual(self.follow_ups(), [])
        self.assertEqual(self.workspace_names(), ["default", "feature"])

    def test_jj_failure_skips_preparation(self) -> None:
        existing = self.root / "occupied"
        existing.mkdir()
        _ = (existing / "file").write_text("occupied\n")
        result = self.workspace_add(str(existing))
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"jj workspace add failed", result.stderr)
        self.assertEqual(self.follow_ups(), [])
        self.assertEqual(self.workspace_names(), ["default"])

    def test_rejects_unsupported_options_and_prints_help_without_creating(self) -> None:
        for arguments, stream, expected in (
            (("-R", str(self.primary), "x"), "stderr", b"-R/--repository is not supported"),
            ((f"--repository={self.primary}", "x"), "stderr", b"-R/--repository is not supported"),
            (("--no-colocate", "x"), "stderr", b"--no-colocate is not supported"),
            (("--name", "n", "--no-colocate", "x"), "stderr", b"--no-colocate is not supported"),
            (("x", "--help"), "stdout", b"usage: jjx workspace add"),
        ):
            with self.subTest(arguments=arguments):
                result = self.workspace_add(*arguments)
                output = result.stdout if stream == "stdout" else result.stderr
                self.assertIn(expected, output)
                self.assertEqual(self.workspace_names(), ["default"])
        self.assertEqual(self.follow_ups(), [])


@final
class DefaultDestinationTests(unittest.TestCase):
    """``jjx workspace add --name NAME`` without a destination uses ~/.worktrees."""

    temporary_directory: TemporaryDirectory[str]
    root: Path
    home: Path
    env: dict[str, str]

    @override
    def setUp(self) -> None:
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name).resolve()
        real_home = self.root / "real-home"
        (real_home / ".config").mkdir(parents=True)
        # HOME names the home directory through a symlink, as /home or /var can.
        self.home = self.root / "home"
        self.home.symlink_to(real_home)
        stubs = self.root / "stubs"
        stubs.mkdir()
        for name in ("worktree-include", "direnv-worktree"):
            stub = stubs / name
            _ = stub.write_text("#!/bin/sh\n")
            stub.chmod(0o755)
        self.env = os.environ | {
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "XDG_STATE_HOME": str(self.home / ".state"),
            "PATH": f"{stubs}{os.pathsep}{os.environ['PATH']}",
            "PYTHONPATH": os.pathsep.join(
                [str(PACKAGE_PARENT), *filter(None, [os.environ.get("PYTHONPATH")])]
            ),
            "JJ_USER": "Test User",
            "JJ_EMAIL": "test@example.com",
        }

    def repository(self, path: Path) -> Path:
        _ = run("git", "init", str(path), env=self.env)
        _ = (path / "tracked").write_text("initial\n")
        _ = run("jj", "git", "init", "--colocate", cwd=path, env=self.env)
        _ = run("jj", "commit", "-m", "initial", cwd=path, env=self.env)
        return path

    def workspace_add(self, *arguments: str, cwd: Path) -> subprocess.CompletedProcess[bytes]:
        return run(
            sys.executable, "-m", "jjx", "workspace", "add", *arguments,
            check=False, cwd=cwd, env=self.env,
        )

    def workspace_names(self, repository: Path) -> list[str]:
        output = run(
            "jj", "workspace", "list", "-T", 'name ++ "\\n"', cwd=repository, env=self.env
        ).stdout
        return sorted(output.decode().splitlines())

    def assert_created(self, result: subprocess.CompletedProcess[bytes], expected: Path) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(os.path.samefile(os.fsdecode(result.stdout.removesuffix(b"\n")), expected))
        top_level = run("git", "-C", str(expected), "rev-parse", "--show-toplevel", env=self.env)
        self.assertTrue(os.path.samefile(os.fsdecode(top_level.stdout.removesuffix(b"\n")), expected))

    def test_creates_under_repository_path_from_home(self) -> None:
        primary = self.repository(self.root / "real-home" / "projects" / "app")
        result = self.workspace_add("--name", "feature", "-r", "@-", "-m", "started", cwd=primary)
        self.assert_created(result, self.home / ".worktrees" / "projects" / "app" / "feature")
        self.assertEqual(self.workspace_names(primary), ["default", "feature"])
        description = run(
            "jj", "log", "-r", "feature@", "--no-graph", "-T", "description",
            cwd=primary, env=self.env,
        ).stdout
        self.assertEqual(description, b"started\n")

    def test_uses_primary_checkout_from_another_workspace(self) -> None:
        primary = self.repository(self.home / "app")
        first = self.workspace_add("--name", "first", cwd=primary)
        workspace = self.home / ".worktrees" / "app" / "first"
        self.assert_created(first, workspace)

        second = self.workspace_add("--name=second", cwd=workspace)
        self.assert_created(second, self.home / ".worktrees" / "app" / "second")
        self.assertEqual(self.workspace_names(primary), ["default", "first", "second"])

    def test_repository_outside_home_uses_absolute_path(self) -> None:
        primary = self.repository(self.root / "srv" / "app")
        result = self.workspace_add("--name", "feature", cwd=primary)
        relative = primary.relative_to(primary.anchor)
        self.assert_created(result, self.home / ".worktrees" / "_" / relative / "feature")

    def test_given_destination_is_used_as_is(self) -> None:
        primary = self.repository(self.home / "app")
        for arguments, expected in (
            (("--name", "one", str(self.root / "one")), self.root / "one"),
            (("--name=two", "-r", "@-", "--", "-two"), primary / "-two"),
            (("-m", "-", "--name", "three", "../three"), self.home / "three"),
        ):
            with self.subTest(arguments=arguments):
                self.assert_created(self.workspace_add(*arguments, cwd=primary), expected)
        self.assertFalse((self.home / ".worktrees").exists())

    def test_existing_destination_fails_without_creating(self) -> None:
        primary = self.repository(self.home / "app")
        existing = self.home / ".worktrees" / "app" / "feature"
        existing.mkdir(parents=True)
        _ = (existing / "file").write_text("occupied\n")
        result = self.workspace_add("--name", "feature", cwd=primary)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"jj workspace add failed", result.stderr)
        self.assertEqual(self.workspace_names(primary), ["default"])
        self.assertEqual(sorted(path.name for path in existing.iterdir()), ["file"])

    def test_without_name_or_destination_keeps_jj_error(self) -> None:
        primary = self.repository(self.home / "app")
        for arguments in ((), ("-m", "message"), ("-r", "@")):
            with self.subTest(arguments=arguments):
                result = self.workspace_add(*arguments, cwd=primary)
                self.assertEqual(result.returncode, 1)
                self.assertIn(b"<DESTINATION>", result.stderr)
        self.assertFalse((self.home / ".worktrees").exists())
        self.assertEqual(self.workspace_names(primary), ["default"])

    def test_rejects_name_that_is_not_one_folder(self) -> None:
        primary = self.repository(self.home / "app")
        for name in ("..", "a/b", ""):
            with self.subTest(name=name):
                result = self.workspace_add("--name", name, cwd=primary)
                self.assertEqual(result.returncode, 1)
                self.assertIn(b"give a destination", result.stderr)
        self.assertFalse((self.home / ".worktrees").exists())


@final
class DestinationArgumentsTests(unittest.TestCase):
    def test_finds_name_and_destination_as_jj_parses_them(self) -> None:
        for arguments, name, has_destination in (
            (["--name", "x"], "x", False),
            (["--name=x"], "x", False),
            (["--name", "x", "--name", "y"], "y", False),
            (["--name", "x", "dest"], "x", True),
            (["-r", "@", "--name", "x"], "x", False),
            (["-r@", "dest"], None, True),
            (["-r=@", "--name", "x"], "x", False),
            (["-m", "message", "--revision", "@", "--sparse-patterns", "full"], None, False),
            (["--message=m", "--sparse-patterns=copy", "--name", "x"], "x", False),
            (["--config", "a=b", "--color", "never", "--name", "x"], "x", False),
            (["--at-op", "@", "--ignore-working-copy", "--name", "x"], "x", False),
            (["--name", "x", "--"], "x", False),
            (["--name", "x", "--", "-dest"], "x", True),
            (["--name", "x", "-"], "x", True),
            (["--colocate", "dest"], None, True),
            (["-m", "--name", "x"], "x", False),
            (["--name", "-m", "message"], None, False),
            (["-m", "-", "--name", "x"], "x", False),
        ):
            with self.subTest(arguments=arguments):
                parsed = workspace_add._parse_destination_arguments(arguments)
                self.assertEqual(parsed.name, name)
                self.assertEqual(parsed.has_destination, has_destination)


if __name__ == "__main__":
    _ = unittest.main()
