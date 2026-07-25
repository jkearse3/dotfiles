#!/usr/bin/env python3
# pyright: reportUninitializedInstanceVariable=false

from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final, override


BIN = Path(os.environ.get("DIRENV_WORKTREE_BIN", Path(__file__).parents[1]))
PROGRAM = Path(os.environ.get("DIRENV_WORKTREE_PROGRAM", Path(__file__).parents[1] / "direnv-worktree.py"))


def run(
    *arguments: str,
    check: bool = True,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        arguments,
        check=check,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


class RepositoryFixture(unittest.TestCase):
    temporary_directory: TemporaryDirectory[str]
    root: Path
    primary: Path
    global_config: Path
    direnv: Path
    log: Path
    hook_log: Path
    command_bin: Path
    command: Path
    env: dict[str, str]

    @override
    def setUp(self) -> None:
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name).resolve()
        self.primary = self.root / "primary"
        self.global_config = self.root / "global.gitconfig"
        self.direnv = self.root / "direnv"
        self.log = self.root / "direnv.log"
        self.hook_log = self.root / "hooks.log"
        self.command_bin = self.root / "bin"
        self.command_bin.mkdir()
        self.command = self.command_bin / "direnv-worktree"
        self.command.symlink_to(PROGRAM)
        _ = self.direnv.write_text(
            """#!/usr/bin/env bash
set -u
command=$1
path=$2
printf '%s %s\\n' "$command" "$path" >>"$DIRENV_TEST_LOG"
case $command in
exec)
  if [[ ! -f $path/.direnv-authorized ]]; then
    echo 'direnv: .envrc is blocked' >&2
    exit 1
  fi
  if [[ -f $path/.direnv-fail || $path == *target-fail* ]]; then
    if [[ -n ${DIRENV_TEST_INTERLEAVED:-} ]]; then
      echo 'direnv: stdout one'
      echo 'direnv: stderr one' >&2
      echo 'direnv: stdout two'
      echo 'direnv: stderr two' >&2
    fi
    echo 'direnv: .envrc evaluation failed' >&2
    exit 1
  fi
  ;;
allow)
  touch "${path%/.envrc}/.direnv-authorized"
  ;;
deny)
  rm -f "${path%/.envrc}/.direnv-authorized"
  ;;
*) exit 2 ;;
esac
"""
        )
        self.direnv.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update(
            {
                "DIRENV_TEST_LOG": str(self.log),
                "DIRENV_WORKTREE_DIRENV": str(self.direnv),
                "GIT_CONFIG_GLOBAL": str(self.global_config),
                "GIT_CONFIG_NOSYSTEM": "1",
                "HOOK_TEST_LOG": str(self.hook_log),
            }
        )
        _ = run("git", "init", str(self.primary), env=self.env)
        _ = run("git", "-C", str(self.primary), "config", "user.name", "Test User", env=self.env)
        _ = run("git", "-C", str(self.primary), "config", "user.email", "test@example.com", env=self.env)
        _ = (self.primary / ".envrc").write_bytes(b"export TEST=value\n")
        _ = (self.primary / "tracked").write_text("initial\n")
        _ = run("git", "-C", str(self.primary), "add", ".envrc", "tracked", env=self.env)
        _ = run("git", "-C", str(self.primary), "commit", "-m", "initial", env=self.env)
        _ = (self.primary / ".direnv-authorized").touch()
        _ = run(
            "git",
            "config",
            "--global",
            "hook.direnv-worktree.command",
            f"{self.command} post-checkout",
            env=self.env,
        )
        _ = run(
            "git",
            "config",
            "--global",
            "hook.direnv-worktree.event",
            "post-checkout",
            env=self.env,
        )

    def invoke(
        self, *arguments: str, cwd: Path | None = None, check: bool = True
    ) -> subprocess.CompletedProcess[bytes]:
        return run(
            str(self.command), *arguments, cwd=cwd or self.primary, check=check, env=self.env
        )

    def enroll(self) -> None:
        _ = self.invoke("enable")
        self.log.unlink(missing_ok=True)

    def calls(self) -> list[str]:
        if not self.log.exists():
            return []
        return self.log.read_text().splitlines()

    def add_worktree(self, name: str, *extra: str, check: bool = True) -> subprocess.CompletedProcess[bytes]:
        return run(
            "git",
            "-C",
            str(self.primary),
            "worktree",
            "add",
            *extra,
            str(self.root / name),
            "HEAD",
            check=check,
            env=self.env,
        )


@final
class HookTests(RepositoryFixture):
    def test_primary_checkout_and_clone_are_noops(self) -> None:
        self.enroll()
        _ = run("git", "-C", str(self.primary), "checkout", "--", "tracked", env=self.env)
        clone = self.root / "clone"
        _ = run("git", "clone", str(self.primary), str(clone), env=self.env)
        self.assertEqual(self.calls(), [])

    def test_ordinary_checkout_in_linked_worktree_is_a_noop(self) -> None:
        linked = self.root / "ordinary"
        _ = self.add_worktree("ordinary", "--detach")
        self.enroll()
        _ = run("git", "-C", str(linked), "checkout", "-b", "ordinary-branch", env=self.env)
        self.assertEqual(self.calls(), [])

    def test_disabled_repository_is_a_noop(self) -> None:
        _ = self.add_worktree("disabled", "--detach")
        self.assertEqual(self.calls(), [])

    def test_repository_without_envrc_is_a_noop(self) -> None:
        self.enroll()
        _ = run("git", "-C", str(self.primary), "rm", ".envrc", env=self.env)
        _ = run("git", "-C", str(self.primary), "commit", "-m", "remove envrc", env=self.env)
        self.log.unlink(missing_ok=True)
        _ = self.add_worktree("no-envrc", "--detach")
        self.assertEqual(self.calls(), [])

    def test_matching_envrc_authorizes_branch_worktree(self) -> None:
        self.enroll()
        target = self.root / "matching"
        _ = self.add_worktree("matching", "-b", "matching")
        self.assertTrue((target / ".direnv-authorized").exists())
        self.assertEqual(self.calls(), [f"exec {self.primary}", f"allow {target}/.envrc", f"exec {target}"])

    def test_composes_once_with_configured_and_traditional_hooks(self) -> None:
        configured = self.root / "configured-hook"
        traditional = self.primary / ".git" / "hooks" / "post-checkout"
        for script, label in ((configured, "configured"), (traditional, "traditional")):
            _ = script.write_text(f'#!/bin/sh\nprintf "%s\\n" {label} >>"$HOOK_TEST_LOG"\n')
            script.chmod(0o755)
        _ = run(
            "git",
            "config",
            "--global",
            "hook.other.command",
            str(configured),
            env=self.env,
        )
        _ = run("git", "config", "--global", "hook.other.event", "post-checkout", env=self.env)
        events = run(
            "git",
            "config",
            "--global",
            "--get-all",
            "hook.direnv-worktree.event",
            env=self.env,
        ).stdout.splitlines()
        self.assertEqual(events, [b"post-checkout"])

        self.enroll()
        target = self.root / "composed"
        _ = self.add_worktree("composed", "--detach")
        self.assertEqual(self.hook_log.read_text().splitlines(), ["configured", "traditional"])
        self.assertEqual(self.calls(), [f"exec {self.primary}", f"allow {target}/.envrc", f"exec {target}"])

    def test_mismatched_envrc_fails_and_preserves_registered_worktree(self) -> None:
        self.enroll()
        first = run("git", "-C", str(self.primary), "rev-parse", "HEAD", env=self.env).stdout.decode().strip()
        _ = (self.primary / ".envrc").write_bytes(b"export TEST=changed\n")
        _ = run("git", "-C", str(self.primary), "commit", "-am", "change envrc", env=self.env)
        _ = run("git", "-C", str(self.primary), "checkout", first, env=self.env)
        self.log.unlink(missing_ok=True)
        result = run(
            "git",
            "-C",
            str(self.primary),
            "worktree",
            "add",
            "--detach",
            str(self.root / "mismatch"),
            "HEAD@{1}",
            check=False,
            env=self.env,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"target .envrc differs", result.stderr)
        self.assertIn(str(self.root / "mismatch"), run("git", "-C", str(self.primary), "worktree", "list", env=self.env).stdout.decode())

    def test_blocked_and_failed_primary_environment_fail(self) -> None:
        self.enroll()
        for name, setup in (
            ("blocked-primary", lambda: (self.primary / ".direnv-authorized").unlink()),
            ("failed-primary", lambda: (self.primary / ".direnv-fail").touch()),
        ):
            with self.subTest(name=name):
                setup()
                result = self.add_worktree(name, "--detach", check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b"primary worktree .envrc is not authorized and evaluable", result.stderr)
                _ = run("git", "-C", str(self.primary), "worktree", "remove", "--force", str(self.root / name), env=self.env)
                _ = (self.primary / ".direnv-authorized").touch()
                (self.primary / ".direnv-fail").unlink(missing_ok=True)

    def test_target_evaluation_failure_revokes_authorization(self) -> None:
        self.enroll()
        target = self.root / "target-fail"
        result = self.add_worktree("target-fail", "--detach", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"target .envrc failed evaluation", result.stderr)
        self.assertFalse((target / ".direnv-authorized").exists())
        self.assertIn(f"deny {target}/.envrc", self.calls())

    def test_detached_linked_worktree_is_authorized(self) -> None:
        self.enroll()
        target = self.root / "detached"
        _ = self.add_worktree("detached", "--detach")
        symbolic = run("git", "-C", str(target), "symbolic-ref", "-q", "HEAD", check=False, env=self.env)
        self.assertNotEqual(symbolic.returncode, 0)
        self.assertTrue((target / ".direnv-authorized").exists())

    def test_newline_ending_linked_worktree_path_is_authorized(self) -> None:
        self.enroll()
        target = self.root / "newline\n"
        _ = self.add_worktree("newline\n", "--detach")
        self.assertTrue((target / ".direnv-authorized").exists())


@final
class EnrollmentTests(RepositoryFixture):
    def test_installed_enable_ignores_exported_git_function(self) -> None:
        marker = self.root / "shadowed-git"
        hostile_env = self.env | {
            "BASH_FUNC_git%%": f'() {{ touch "{marker}"; return 1; }}',
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_DATA_HOME": str(self.root / "data"),
        }
        result = run(
            str(BIN / "direnv-worktree"),
            "enable",
            cwd=self.primary,
            check=False,
            env=hostile_env,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(marker.exists())

    def test_installed_enable_ignores_direnv_executable_override(self) -> None:
        secure_env = self.env | {
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_DATA_HOME": str(self.root / "data"),
        }
        result = run(
            str(BIN / "direnv-worktree"),
            "enable",
            cwd=self.primary,
            check=False,
            env=secure_env,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"primary worktree .envrc is not authorized and evaluable", result.stderr)
        configured = run(
            "git",
            "-C",
            str(self.primary),
            "config",
            "--local",
            "--get",
            "direnv.worktreeAutoAllow",
            check=False,
            env=self.env,
        )
        self.assertEqual(configured.returncode, 1)

    def test_enable_and_disable_are_idempotent_and_shared(self) -> None:
        _ = self.invoke("enable")
        _ = self.invoke("enable")
        self.assertEqual(
            run(
                "git",
                "-C",
                str(self.primary),
                "config",
                "--local",
                "--get-all",
                "direnv.worktreeAutoAllow",
                env=self.env,
            ).stdout.splitlines(),
            [b"true"],
        )
        approval = self.primary / ".direnv-authorized"
        _ = self.invoke("disable")
        _ = self.invoke("disable")
        self.assertTrue(approval.exists())
        result = run(
            "git",
            "-C",
            str(self.primary),
            "config",
            "--local",
            "--get",
            "direnv.worktreeAutoAllow",
            check=False,
            env=self.env,
        )
        self.assertEqual(result.returncode, 1)

    def test_enable_rejects_blocked_primary_environment(self) -> None:
        (self.primary / ".direnv-authorized").unlink()
        result = self.invoke("enable", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"primary worktree .envrc is not authorized and evaluable", result.stderr)

    def test_direnv_diagnostics_preserve_output_order(self) -> None:
        self.env["DIRENV_TEST_INTERLEAVED"] = "1"
        (self.primary / ".direnv-fail").touch()
        result = self.invoke("enable", check=False)
        messages = (
            b"direnv: stdout one",
            b"direnv: stderr one",
            b"direnv: stdout two",
            b"direnv: stderr two",
        )
        positions = [result.stderr.index(message) for message in messages]
        self.assertEqual(positions, sorted(positions))

    def test_enable_preserves_git_failure_diagnostics(self) -> None:
        git_wrapper = self.root / "failing-git"
        _ = git_wrapper.write_text(
            """#!/bin/sh
case "$*" in
  *"config --local --type=bool direnv.worktreeAutoAllow true"*)
    echo 'git: config failed' >&2
    exit 1
    ;;
esac
exec git "$@"
"""
        )
        git_wrapper.chmod(0o755)
        self.env["DIRENV_WORKTREE_GIT"] = str(git_wrapper)
        result = self.invoke("enable", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"git: config failed", result.stderr)


if __name__ == "__main__":
    _ = unittest.main()
