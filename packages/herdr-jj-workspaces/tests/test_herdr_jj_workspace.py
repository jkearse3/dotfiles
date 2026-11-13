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
# with workspace w2 and pane w2:p1, refusing as Herdr does to open from the
# linked workspace w2, and workspace list with $HERDR_STUB_WORKSPACES.
HERDR_STUB = """\
#!/bin/sh
printf '%s\\n' "$*" >> "$HERDR_STUB_LOG"
case "$1 $2" in
  "worktree list")
    [ -n "${HERDR_STUB_SOURCE:-}" ] || exit 1
    printf '{"result":{"source":%s}}\\n' "$HERDR_STUB_SOURCE" ;;
  "worktree open")
    [ "$4" != w2 ] || exit 1
    printf '{"result":{"workspace":{"workspace_id":"w2"},"root_pane":{"pane_id":"w2:p1"}}}\\n' ;;
  "workspace list")
    printf '%s\\n' "$HERDR_STUB_WORKSPACES" ;;
  *)
    printf '{"result":{}}\\n' ;;
esac
"""

# fzf, named by $HERDR_JJ_WORKSPACE_FZF_PATH, as prompt-add runs it to pick the
# base revision: records its input lines in $FAKE_FZF_BASE_INPUT, then prints
# input line ${FAKE_FZF_BASE_CHOICE:-1}, as Enter with an empty query does, and
# exits with ${FAKE_FZF_BASE_STATUS:-0}.
FAKE_FZF = """\
#!/bin/sh
cat > "$FAKE_FZF_BASE_INPUT"
sed -n "${FAKE_FZF_BASE_CHOICE:-1}p" "$FAKE_FZF_BASE_INPUT"
exit "${FAKE_FZF_BASE_STATUS:-0}"
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
        fzf = self.root / "fzf"
        _ = fzf.write_text(FAKE_FZF)
        fzf.chmod(0o755)
        self.fzf_base_input = self.root / "fzf-base.input"
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
            "HERDR_JJ_WORKSPACE_FZF_PATH": str(fzf),
            "FAKE_FZF_BASE_INPUT": str(self.fzf_base_input),
            "HERDR_STUB_SOURCE": json.dumps(
                {"repo_root": str(self.repo), "repo_name": "repo", "source_workspace_id": "w1"}
            ),
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

    def change_id(self, revision: str) -> str:
        return self.jj("log", "--no-graph", "-r", revision, "-T", "change_id.shortest(8)")

    def create_bookmarks_to_stack_on(self) -> None:
        """Bookmark base on the initial commit and newer on a later sibling, so neither is trunk()."""
        _ = self.jj("bookmark", "create", "base", "-r", "@-")
        _ = subprocess.run(
            ["jj", "-R", str(self.repo), "new", "--no-edit", "@-", "-m", "later"],
            env={**self.env, "JJ_TIMESTAMP": "2100-01-01T00:00:00Z"},
            check=True,
            capture_output=True,
        )
        _ = self.jj("bookmark", "create", "newer", "-r", 'description(substring:"later")')

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

    def test_add_with_revision_starts_on_that_revision(self) -> None:
        # trunk() is root() here, so a workspace on trunk() would not start on base.
        _ = self.jj("bookmark", "create", "base", "-r", "@-")

        result = self.run_cli("add", "feature", "--revision", "base")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commit("feature@-"), self.commit("base"))
        self.assertNotEqual(self.commit("feature@-"), self.commit("trunk()"))

    def test_add_uses_named_workspace_and_focus(self) -> None:
        result = self.run_cli("add", "feature", "--workspace", "w7", "--focus", HERDR_WORKSPACE_ID="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.herdr_calls(),
            ["worktree list --workspace w7", f"worktree open --workspace w1 --path {self.workspace} --focus"],
        )

    def test_add_from_jj_workspace_opens_from_primary_checkout(self) -> None:
        self.add_feature()
        result = self.run_cli("add", "second", HERDR_WORKSPACE_ID="w2")
        self.assertEqual(result.returncode, 0, result.stderr)
        second = self.workspace.parent / "second"
        self.assertEqual(
            json.loads(result.stdout),
            {"path": str(second), "workspace_id": "w2", "pane_id": "w2:p1"},
        )
        self.assertEqual(sorted(self.workspace_names()), ["default", "feature", "second"])
        self.assertEqual(
            self.herdr_calls(),
            ["worktree list --workspace w2", f"worktree open --workspace w1 --path {second} --no-focus"],
        )

    def test_add_without_reported_parent_opens_from_caller(self) -> None:
        source = json.dumps({"repo_root": str(self.repo), "repo_name": "repo"})
        result = self.run_cli("add", "feature", "--workspace", "w7", HERDR_STUB_SOURCE=source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.herdr_calls(),
            ["worktree list --workspace w7", f"worktree open --workspace w7 --path {self.workspace} --no-focus"],
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
        self.assertLess(result.stdout.index("Base: trunk()"), result.stdout.index("Name: "))
        self.assertEqual(
            self.herdr_calls(),
            ["worktree list --workspace w1", f"worktree open --workspace w1 --path {self.workspace} --focus"],
        )
        # Without bookmarks there is no base to choose, so fzf never runs.
        self.assertFalse(self.fzf_base_input.exists())
        self.assertEqual(self.commit("feature@-"), self.commit("trunk()"))

    def test_prompt_add_invalid_name_after_base_creates_nothing(self) -> None:
        self.create_bookmarks_to_stack_on()
        result = self.run_cli("prompt-add", stdin="../escape\n\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("one path component", result.stderr)
        self.assertIn("Press enter to close.", result.stderr)
        self.assertTrue(self.fzf_base_input.exists())
        self.assertEqual(self.workspace_names(), ["default"])
        self.assertEqual(self.herdr_calls(), ["worktree list --workspace w1"])

    def test_prompt_add_base_enter_keeps_trunk(self) -> None:
        self.create_bookmarks_to_stack_on()
        result = self.run_cli("prompt-add", stdin="feature\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(result.stdout.index("Base: trunk()"), result.stdout.index("Name: "))
        self.assertEqual(
            self.fzf_base_input.read_text().splitlines(),
            [
                "trunk()",
                f"newer  {self.change_id('newer')}  later",
                f"base   {self.change_id('base')}  initial",
            ],
        )
        self.assertEqual(self.commit("feature@-"), self.commit("trunk()"))

    def test_prompt_add_base_bookmark_starts_on_it(self) -> None:
        self.create_bookmarks_to_stack_on()
        result = self.run_cli("prompt-add", stdin="feature\n", FAKE_FZF_BASE_CHOICE="3")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"Base: base  {self.change_id('base')}  initial\n", result.stdout)
        self.assertEqual(self.commit("feature@-"), self.commit("base"))
        self.assertIn("feature", self.workspace_names())

    def test_prompt_add_base_closed_without_choosing_creates_nothing(self) -> None:
        self.create_bookmarks_to_stack_on()
        for status in ("1", "130"):
            with self.subTest(status=status):
                result = self.run_cli("prompt-add", stdin="", FAKE_FZF_BASE_STATUS=status)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("Name: ", result.stdout)
                self.assertEqual(self.workspace_names(), ["default"])
                self.assertFalse(self.workspace.exists())
                self.assertEqual(self.herdr_calls(), ["worktree list --workspace w1"])

    def test_prompt_add_base_leaves_out_deleted_bookmarks(self) -> None:
        # A bookmark deleted locally but still on a tracked remote stays listed by jj as deleted.
        remote = self.root / "remote.git"
        _ = subprocess.run(["git", "init", "--bare", str(remote)], env=self.env, check=True, capture_output=True)
        _ = self.jj("git", "remote", "add", "origin", str(remote))
        _ = self.jj("bookmark", "create", "gone", "kept", "-r", "@-")
        _ = self.jj("git", "push", "--bookmark", "gone")
        _ = self.jj("bookmark", "delete", "gone")

        result = self.run_cli("prompt-add", stdin="feature\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.fzf_base_input.read_text().splitlines(),
            ["trunk()", f"kept  {self.change_id('kept')}  initial"],
        )

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
