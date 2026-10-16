from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import final, override

CLI = os.environ["HERDR_JJ_WORKSPACE"]

# Records each call, one per line; answers worktree list with $HERDR_STUB_SOURCE,
# or fails as Herdr does outside a repository when it is unset, worktree open
# with workspace w2 and pane w2:p1, and workspace list with
# $HERDR_STUB_WORKSPACES.
HERDR_STUB = """\
#!/bin/sh
printf '%s\\n' "$*" >> "$HERDR_STUB_LOG"
case "$1 $2" in
  "worktree list")
    [ -n "${HERDR_STUB_SOURCE:-}" ] || exit 1
    printf '{"result":{"source":%s}}\\n' "$HERDR_STUB_SOURCE" ;;
  "worktree open")
    printf '{"result":{"workspace":{"workspace_id":"w2"},"root_pane":{"pane_id":"w2:p1"}}}\\n' ;;
  "workspace list")
    printf '%s\\n' "$HERDR_STUB_WORKSPACES" ;;
  *)
    printf '{"result":{}}\\n' ;;
esac
"""


@final
class HerdrJjWorkspaceTests(unittest.TestCase):
    @override
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        home = self.root / "home"
        home.mkdir()
        stub = self.root / "herdr"
        _ = stub.write_text(HERDR_STUB)
        stub.chmod(0o755)
        self.log = self.root / "herdr.log"
        self.log.touch()
        self.repo = self.root / "repo"
        self.workspace = home / ".herdr" / "worktrees" / "repo" / "feature"
        gitconfig = self.root / "gitconfig"
        gitconfig.touch()
        self.env = {
            **os.environ,
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "GIT_CONFIG_GLOBAL": str(gitconfig),
            "GIT_CONFIG_NOSYSTEM": "1",
            "JJ_USER": "Test User",
            "JJ_EMAIL": "test@example.com",
            "HERDR_BIN_PATH": str(stub),
            "HERDR_STUB_LOG": str(self.log),
            "HERDR_STUB_SOURCE": json.dumps({"repo_root": str(self.repo), "repo_name": "repo"}),
            "HERDR_STUB_WORKSPACES": json.dumps(
                {
                    "result": {
                        "workspaces": [
                            {
                                "workspace_id": "w9",
                                "worktree": {"repo_root": "/elsewhere", "is_linked_worktree": False},
                            },
                            {
                                "workspace_id": "w2",
                                "worktree": {
                                    "repo_root": str(self.repo),
                                    "checkout_path": str(self.workspace),
                                    "is_linked_worktree": True,
                                },
                            },
                            {
                                "workspace_id": "w1",
                                "worktree": {
                                    "repo_root": str(self.repo),
                                    "checkout_path": str(self.repo),
                                    "is_linked_worktree": False,
                                },
                            },
                        ]
                    }
                }
            ),
            "HERDR_PLUGIN_CONTEXT_JSON": json.dumps({"workspace_id": "w1"}),
            "HERDR_WORKSPACE_ID": "w1",
        }
        _ = subprocess.run(["git", "init", "--initial-branch=main", str(self.repo)], env=self.env, check=True, capture_output=True)
        (self.repo / "tracked").touch()
        for command in (["jj", "git", "init", "--colocate"], ["jj", "commit", "-m", "initial"]):
            _ = subprocess.run(command, cwd=self.repo, env=self.env, check=True, capture_output=True)

    def run_cli(self, *arguments: str, stdin: str = "", **env: str) -> subprocess.CompletedProcess[str]:
        _ = self.log.write_text("")
        return subprocess.run(
            [CLI, *arguments], input=stdin, env={**self.env, **env}, text=True, capture_output=True, check=False
        )

    def herdr_calls(self) -> list[str]:
        return self.log.read_text().splitlines()

    def jj(self, *arguments: str) -> str:
        return subprocess.run(
            ["jj", "-R", str(self.repo), *arguments], env=self.env, check=True, capture_output=True, text=True
        ).stdout

    def workspace_names(self) -> list[str]:
        return self.jj("workspace", "list", "-T", 'name ++ "\\n"').splitlines()

    def commit(self, revision: str) -> str:
        return self.jj("log", "--no-graph", "-r", revision, "-T", "commit_id")

    def add_feature(self) -> None:
        result = self.run_cli("add", "feature")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_add_creates_workspace_from_trunk_without_moving_focus(self) -> None:
        result = self.run_cli("add", "feature")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout),
            {"path": str(self.workspace), "workspace_id": "w2", "pane_id": "w2:p1"},
        )
        self.assertTrue((self.workspace / ".jj" / "repo").is_file())
        self.assertIn("feature", self.workspace_names())
        self.assertEqual(
            self.herdr_calls(),
            ["worktree list --workspace w1", f"worktree open --workspace w1 --path {self.workspace} --no-focus"],
        )
        # The workspace starts from trunk, not from the primary checkout's unfinished @.
        self.assertEqual(self.commit("feature@-"), self.commit("trunk()"))
        self.assertNotEqual(self.commit("feature@-"), self.commit("default@-"))

    def test_add_uses_named_workspace_and_focus(self) -> None:
        result = self.run_cli("add", "feature", "--workspace", "w7", "--focus", HERDR_WORKSPACE_ID="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.herdr_calls(),
            ["worktree list --workspace w7", f"worktree open --workspace w7 --path {self.workspace} --focus"],
        )

    def test_add_outside_herdr_needs_workspace(self) -> None:
        result = self.run_cli("add", "feature", HERDR_WORKSPACE_ID="")
        self.assertEqual(result.returncode, 1)
        self.assertIn("pass --workspace", result.stderr)
        self.assertEqual(self.herdr_calls(), [])

    def test_add_outside_repository_fails_without_touching_jj(self) -> None:
        result = self.run_cli("add", "outside", HERDR_STUB_SOURCE="")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not in a Git repository", result.stderr)
        self.assertEqual(self.herdr_calls(), ["worktree list --workspace w1"])
        self.assertEqual(self.workspace_names(), ["default"])

    def test_add_rejects_invalid_and_existing_names(self) -> None:
        for name in ("../escape", "-x", ".."):
            with self.subTest(name=name):
                result = self.run_cli("add", "--", name)
                self.assertEqual(result.returncode, 1)
                self.assertIn("one path component", result.stderr)
                self.assertEqual(self.herdr_calls(), [])
        self.add_feature()
        result = self.run_cli("add", "feature")
        self.assertEqual(result.returncode, 1)
        self.assertIn("already exists", result.stderr)
        self.assertEqual(self.herdr_calls(), ["worktree list --workspace w1"])
        self.assertEqual(sorted(self.workspace_names()), ["default", "feature"])

    def test_remove_dry_run_changes_nothing(self) -> None:
        self.add_feature()
        result = self.run_cli("remove", "--workspace", "w2", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("would remove jj workspace feature", result.stdout)
        self.assertTrue(self.workspace.is_dir())
        self.assertEqual(self.herdr_calls(), ["workspace list"])

    def test_remove_refuses_primary_checkout(self) -> None:
        result = self.run_cli("remove")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not a removable jj workspace", result.stderr)
        self.assertTrue((self.repo / ".jj").is_dir())
        self.assertEqual(self.herdr_calls(), ["workspace list"])

    def test_remove_refuses_unknown_workspace(self) -> None:
        result = self.run_cli("remove", "--workspace", "w5")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not a Git worktree", result.stderr)

    def test_remove_deletes_workspace_and_closes_it_without_moving_focus(self) -> None:
        self.add_feature()
        result = self.run_cli("remove", "--workspace", "w2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("removed jj workspace feature", result.stdout)
        self.assertFalse(self.workspace.exists())
        self.assertEqual(self.workspace_names(), ["default"])
        self.assertEqual(self.herdr_calls(), ["workspace list", "workspace close w2"])

    def test_remove_with_focus_focuses_primary_checkout(self) -> None:
        self.add_feature()
        result = self.run_cli("remove", "--workspace", "w2", "--focus")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.herdr_calls(), ["workspace list", "workspace list", "workspace close w2", "workspace focus w1"]
        )

    def test_prompt_add_creates_and_focuses(self) -> None:
        result = self.run_cli("prompt-add", stdin="feature\n", HERDR_WORKSPACE_ID="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("New jj workspace for repo", result.stdout)
        self.assertEqual(
            self.herdr_calls(),
            ["worktree list --workspace w1", f"worktree open --workspace w1 --path {self.workspace} --focus"],
        )

    def test_prompt_add_error_waits_for_enter(self) -> None:
        result = self.run_cli("prompt-add", stdin="../escape\n\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Press enter to close.", result.stderr)
        self.assertEqual(self.workspace_names(), ["default"])

    def test_prompt_remove_declined_changes_nothing(self) -> None:
        self.add_feature()
        result = self.run_cli("prompt-remove", stdin="n\n", HERDR_PLUGIN_CONTEXT_JSON=json.dumps({"workspace_id": "w2"}))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.workspace.is_dir())
        self.assertEqual(self.herdr_calls(), ["workspace list"])

    def test_prompt_remove_confirmed_removes_and_focuses_primary(self) -> None:
        self.add_feature()
        result = self.run_cli("prompt-remove", stdin="y\n", HERDR_PLUGIN_CONTEXT_JSON=json.dumps({"workspace_id": "w2"}))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.workspace.exists())
        self.assertEqual(
            self.herdr_calls(), ["workspace list", "workspace list", "workspace close w2", "workspace focus w1"]
        )

    def test_open_popup_opens_entrypoint(self) -> None:
        result = self.run_cli("open-popup", "add-prompt", HERDR_PLUGIN_ID="dotfiles.jj-workspaces")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.herdr_calls(),
            ["plugin pane open --plugin dotfiles.jj-workspaces --entrypoint add-prompt --focus"],
        )


if __name__ == "__main__":
    _ = unittest.main()
