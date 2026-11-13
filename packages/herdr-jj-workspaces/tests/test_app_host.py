"""herdr-jj-workspace driving the Herdr desktop app (--host app) through fake herdr-app and hc executables."""

from __future__ import annotations

import errno
import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path
from typing import cast, final, override

CLI = os.environ["HERDR_JJ_WORKSPACE"]

# Each fake records its call as "<program> <arguments>" in $STUB_LOG.
#
# herdr-app: ls prints $APP_STUB_WORLD, or with $APP_STUB_NO_WINDOW set fails as
# herdr-app does when no window is open; do space.new replies with space sp9,
# tab tb9 and terminal t9, and any other do succeeds, unless its command is
# $APP_STUB_FAIL_DO, when it replies with $APP_STUB_ERROR as herdr-app does.
FAKE_HERDR_APP = """\
#!/bin/sh
printf 'herdr-app %s\\n' "$*" >> "$STUB_LOG"
case "$1" in
  ls)
    if [ -n "${APP_STUB_NO_WINDOW:-}" ]; then
      printf '%s\\n' 'herdr-app: no Herdr window at /app/herdr-app.sock: No such file or directory (os error 2)' >&2
      exit 2
    fi
    printf '%s\\n' "$APP_STUB_WORLD" ;;
  do)
    if [ "$2" = "${APP_STUB_FAIL_DO:-}" ]; then
      printf '{\\n  "error": "%s"\\n}\\n' "$APP_STUB_ERROR"
      exit 1
    fi
    case "$2" in
      space.new) printf '{\\n  "space": "sp9",\\n  "tab": "tb9",\\n  "terminal": "t9"\\n}\\n' ;;
      *) printf '{\\n  "ok": true\\n}\\n' ;;
    esac ;;
  *)
    exit 2 ;;
esac
"""

# hc: get TERMINAL prints $HC_STUB_RECORDS/TERMINAL.json, or fails as hc does
# for an unknown terminal when there is no such file.
FAKE_HC = """\
#!/bin/sh
printf 'hc %s\\n' "$*" >> "$STUB_LOG"
case "$1" in
  get)
    if [ -f "$HC_STUB_RECORDS/$2.json" ]; then
      cat "$HC_STUB_RECORDS/$2.json"
    else
      printf '{"error":{"kind":"not_found","hint":"see hc ls","message":"no terminal %s"}}\\n' "$2" >&2
      exit 1
    fi ;;
  *) exit 2 ;;
esac
"""

# The TUI's herdr, named by $HERDR_BIN_PATH, which an app-host command must never call.
FAKE_HERDR = """\
#!/bin/sh
printf 'herdr %s\\n' "$*" >> "$STUB_LOG"
exit 1
"""

# fzf, named by $HERDR_JJ_WORKSPACE_FZF_PATH. Picking the repository and base
# together, it records its arguments, one per line, in $FAKE_FZF_ARGUMENTS and
# its input lines in $FAKE_FZF_INPUT, then prints input line $FAKE_FZF_CHOICE
# and exits 0, or, with no choice, exits 130 as fzf does on Esc;
# $FAKE_FZF_STATUS overrides the status. With $FAKE_FZF_EARLY_EXIT set, it
# instead reads only the first input line, prints it and exits 0 at once, as
# Enter does before the list is complete. Picking the base revision alone, it
# records its arguments in $FAKE_FZF_BASE_ARGUMENTS and its input lines in
# $FAKE_FZF_BASE_INPUT, then prints input line ${FAKE_FZF_BASE_CHOICE:-1}, as
# Enter with an empty query does, and exits with ${FAKE_FZF_BASE_STATUS:-0}.
# With $EVENT_LOG set, it first appends "fzf started" to that file.
FAKE_FZF = """\
#!/bin/sh
if [ -n "${EVENT_LOG:-}" ]; then
  echo "fzf started" >> "$EVENT_LOG"
fi
for argument; do
  if [ "$argument" = "--prompt=Base revision> " ]; then
    printf '%s\\n' "$@" > "$FAKE_FZF_BASE_ARGUMENTS"
    cat > "$FAKE_FZF_BASE_INPUT"
    sed -n "${FAKE_FZF_BASE_CHOICE:-1}p" "$FAKE_FZF_BASE_INPUT"
    exit "${FAKE_FZF_BASE_STATUS:-0}"
  fi
done
printf '%s\\n' "$@" > "$FAKE_FZF_ARGUMENTS"
if [ -n "${FAKE_FZF_EARLY_EXIT:-}" ]; then
  IFS= read -r line
  printf '%s\\n' "$line"
  exit 0
fi
cat > "$FAKE_FZF_INPUT"
if [ -n "${FAKE_FZF_CHOICE:-}" ]; then
  sed -n "${FAKE_FZF_CHOICE}p" "$FAKE_FZF_INPUT"
  exit "${FAKE_FZF_STATUS:-0}"
fi
exit "${FAKE_FZF_STATUS:-130}"
"""


def app_space(space_id: str, folder: Path, terminal: str, *, shown: bool = False) -> dict[str, object]:
    """Return a space on this machine with one tab showing TERMINAL, shaped like one in ``herdr-app ls``."""
    return {
        "id": space_id,
        "name": folder.name,
        "folder": str(folder),
        "machine": None,
        "active": shown,
        "tabs": [
            {
                "id": f"tb-{space_id}",
                "name": "1",
                "active": True,
                "settled": False,
                "terminals": [
                    {
                        "terminal": terminal,
                        "pane": f"p-{terminal}",
                        "status": None,
                        "app": None,
                        "name": None,
                        "sub_agents": [],
                    }
                ],
            }
        ],
    }


def terminal_record(address: str, start: Path, now: Path | None, space_id: str) -> dict[str, object]:
    """Return a terminal shaped like ``hc get --json``'s, started in START and now in NOW."""
    record: dict[str, object] = {
        "address": address,
        "state": "live",
        "cwd": str(start),
        "labels": {"herdr.space": space_id, "herdr.tab": f"tb-{space_id}"},
    }
    if now is not None:
        record["foreground"] = {"pid": 42, "name": "fish", "argv": ["fish"], "cwd": str(now)}
    return record


@final
class AppHostTests(unittest.TestCase):
    @override
    def setUp(self) -> None:
        # Resolved, so paths the CLI resolves compare equal on macOS's /var -> /private/var.
        self.root = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, self.root)
        home = self.root / "home"
        home.mkdir()
        stubs = self.root / "stubs"
        stubs.mkdir()
        fakes = (("herdr-app", FAKE_HERDR_APP), ("hc", FAKE_HC), ("herdr", FAKE_HERDR), ("fzf", FAKE_FZF))
        for name, script in fakes:
            stub = stubs / name
            _ = stub.write_text(script)
            stub.chmod(0o755)
        self.log = self.root / "stub.log"
        self.records = self.root / "records"
        self.records.mkdir()
        self.fzf_input = self.root / "fzf.input"
        self.fzf_arguments = self.root / "fzf.arguments"
        self.fzf_base_input = self.root / "fzf-base.input"
        self.fzf_base_arguments = self.root / "fzf-base.arguments"
        self.repo = self.root / "repo"
        self.workspace = home / ".herdr" / "worktrees" / "repo" / "feature"
        gitconfig = self.root / "gitconfig"
        gitconfig.touch()

        inherited = {
            name: value
            for name, value in os.environ.items()
            if not name.startswith(("HERDR_", "HC_"))
        }
        self.env = {
            **inherited,
            "PATH": f"{stubs}{os.pathsep}{os.environ['PATH']}",
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "GIT_CONFIG_GLOBAL": str(gitconfig),
            "GIT_CONFIG_NOSYSTEM": "1",
            "JJ_USER": "Test User",
            "JJ_EMAIL": "test@example.com",
            "HERDR_BIN_PATH": str(stubs / "herdr"),
            "STUB_LOG": str(self.log),
            "HC_STUB_RECORDS": str(self.records),
            "HC_TERMINAL_ID": "t1",
            "HERDR_JJ_WORKSPACE_FZF_PATH": str(stubs / "fzf"),
            "FAKE_FZF_INPUT": str(self.fzf_input),
            "FAKE_FZF_ARGUMENTS": str(self.fzf_arguments),
            "FAKE_FZF_BASE_INPUT": str(self.fzf_base_input),
            "FAKE_FZF_BASE_ARGUMENTS": str(self.fzf_base_arguments),
        }
        _ = subprocess.run(
            ["git", "init", "--initial-branch=main", str(self.repo)], env=self.env, check=True, capture_output=True
        )
        (self.repo / "tracked").touch()
        (self.repo / "src").mkdir()
        for command in (["jj", "git", "init", "--colocate"], ["jj", "commit", "-m", "initial"]):
            _ = subprocess.run(command, cwd=self.repo, env=self.env, check=True, capture_output=True)

        # Space sp1 shows the primary checkout, its terminal t1 now in a
        # subdirectory; sp2 shows the feature workspace once it exists.
        self.set_world(
            app_space("sp1", self.repo, "t1", shown=True),
            app_space("sp2", self.workspace, "t2"),
        )
        self.set_record(terminal_record("t1", self.repo, self.repo / "src", "sp1"))
        self.set_record(terminal_record("t2", self.workspace, self.workspace, "sp2"))

    def set_world(self, *spaces: dict[str, object]) -> None:
        self.env["APP_STUB_WORLD"] = json.dumps({"spaces": list(spaces), "recent": []})

    def set_record(self, record: dict[str, object]) -> None:
        _ = (self.records / f"{record['address']}.json").write_text(json.dumps(record))

    def run_cli(
        self, *arguments: str, cwd: Path | None = None, stdin: str = "", **env: str
    ) -> subprocess.CompletedProcess[str]:
        _ = self.log.write_text("")
        return subprocess.run(
            [CLI, *arguments],
            cwd=cwd if cwd is not None else self.repo / "src",
            input=stdin,
            env={**self.env, **env},
            text=True,
            capture_output=True,
            check=False,
            # A picker that never finishes would otherwise hang the suite.
            timeout=120,
        )

    def output(self, result: subprocess.CompletedProcess[str]) -> dict[str, str]:
        return cast(dict[str, str], json.loads(result.stdout))

    def calls(self) -> list[str]:
        return self.log.read_text().splitlines()

    def jj(self, *arguments: str) -> str:
        return subprocess.run(
            ["jj", "-R", str(self.repo), *arguments], env=self.env, check=True, capture_output=True, text=True
        ).stdout

    def workspace_names(self) -> list[str]:
        return sorted(self.jj("workspace", "list", "-T", 'name ++ "\\n"').splitlines())

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

    def create_bookmark_described(self, name: str, description: str) -> None:
        """Bookmark NAME on a new child of the initial commit whose description is DESCRIPTION."""
        _ = self.jj("new", "--no-edit", "@-", "-m", description)
        _ = self.jj("bookmark", "create", name, "-r", "latest(@-+ ~ @)")

    def push_main_as_trunk(self) -> None:
        """Bookmark main on the initial commit and push it to origin, so trunk() resolves to main@origin."""
        remote = self.root / "remote.git"
        _ = subprocess.run(["git", "init", "--bare", str(remote)], env=self.env, check=True, capture_output=True)
        _ = self.jj("git", "remote", "add", "origin", str(remote))
        _ = self.jj("bookmark", "create", "main", "-r", "@-")
        _ = self.jj("git", "push", "--bookmark", "main")

    def add_feature(self) -> None:
        result = self.run_cli("add", "feature", "--host", "app", "--focus")
        self.assertEqual(result.returncode, 0, result.stderr)

    # Host detection

    def test_app_terminal_defaults_to_app_host(self) -> None:
        result = self.run_cli("add", "feature")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[0], "herdr-app ls")

    def test_tui_pane_inside_app_terminal_defaults_to_tui_host(self) -> None:
        result = self.run_cli("add", "feature", HERDR_ENV="1", HERDR_WORKSPACE_ID="w1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.calls(), ["herdr worktree list --workspace w1"])

    def test_host_option_overrides_detection(self) -> None:
        result = self.run_cli("add", "feature", "--host", "tui", HERDR_WORKSPACE_ID="w1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.calls(), ["herdr worktree list --workspace w1"])

    # add

    def test_add_creates_workspace_from_trunk_and_keeps_the_shown_space(self) -> None:
        result = self.run_cli("add", "feature", "--host", "app")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout),
            {"path": str(self.workspace), "workspace_id": "sp9", "pane_id": "t9"},
        )
        self.assertTrue((self.workspace / ".jj" / "repo").is_file())
        self.assertEqual(self.workspace_names(), ["default", "feature"])
        self.assertEqual(self.commit("feature@-"), self.commit("trunk()"))
        self.assertEqual(
            self.calls(),
            [
                "herdr-app ls",
                f'herdr-app do space.new {{"folder": "{self.workspace}"}}',
                'herdr-app do space.select {"id": "sp1"}',
            ],
        )

    def test_add_with_revision_starts_on_that_revision(self) -> None:
        # trunk() is root() here, so a workspace on trunk() would not start on base.
        _ = self.jj("bookmark", "create", "base", "-r", "@-")

        result = self.run_cli("add", "feature", "--host", "app", "--revision", "base")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commit("feature@-"), self.commit("base"))
        self.assertNotEqual(self.commit("feature@-"), self.commit("trunk()"))

    def test_add_with_focus_shows_the_new_space(self) -> None:
        result = self.run_cli("add", "feature", "--host", "app", "--focus")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.calls(), ["herdr-app ls", f'herdr-app do space.new {{"folder": "{self.workspace}"}}']
        )

    def test_add_from_jj_workspace_uses_primary_checkout_repository(self) -> None:
        self.add_feature()
        result = self.run_cli("add", "second", "--host", "app", "--focus", cwd=self.workspace)
        self.assertEqual(result.returncode, 0, result.stderr)
        second = self.workspace.parent / "second"
        self.assertEqual(self.output(result)["path"], str(second))
        self.assertEqual(self.workspace_names(), ["default", "feature", "second"])

    def test_add_with_workspace_uses_that_space_terminal_folder(self) -> None:
        self.add_feature()
        result = self.run_cli("add", "second", "--host", "app", "--workspace", "sp2", cwd=self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[:3], ["herdr-app ls", "hc get t2 --json", "herdr-app ls"])
        self.assertEqual(self.workspace_names(), ["default", "feature", "second"])

    def test_add_falls_back_to_terminal_start_folder(self) -> None:
        self.set_record(terminal_record("t1", self.repo, None, "sp1"))
        result = self.run_cli("add", "feature", "--host", "app", "--workspace", "sp1", cwd=self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.workspace_names(), ["default", "feature"])

    def test_add_outside_jj_fails_before_calling_herdr(self) -> None:
        plain = self.root / "plain"
        plain.mkdir()
        result = self.run_cli("add", "feature", "--host", "app", cwd=plain)
        self.assertEqual(result.returncode, 1)
        self.assertIn("is not in a jj repository; run jjx ensure", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_add_without_window_fails_before_creating_workspace(self) -> None:
        result = self.run_cli("add", "feature", "--host", "app", APP_STUB_NO_WINDOW="1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("herdr-app ls failed: herdr-app: no Herdr window", result.stderr)
        self.assertEqual(self.workspace_names(), ["default"])
        self.assertFalse(self.workspace.exists())

    def test_add_reports_created_workspace_the_app_could_not_open(self) -> None:
        result = self.run_cli(
            "add", "feature", "--host", "app", APP_STUB_FAIL_DO="space.new", APP_STUB_ERROR="no folder"
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn(f"created {self.workspace}, but the Herdr app could not open it", result.stderr)
        self.assertIn("no folder", result.stderr)
        self.assertEqual(self.workspace_names(), ["default", "feature"])

    def test_add_warns_when_the_shown_space_cannot_be_shown_again(self) -> None:
        result = self.run_cli(
            "add", "feature", "--host", "app", APP_STUB_FAIL_DO="space.select", APP_STUB_ERROR="no such space"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output(result)["workspace_id"], "sp9")
        self.assertIn("warning:", result.stderr)
        self.assertIn("no such space", result.stderr)

    def test_add_rejects_invalid_name_without_calling_herdr(self) -> None:
        result = self.run_cli("add", "--host", "app", "--", "../escape")
        self.assertEqual(result.returncode, 1)
        self.assertIn("one path component", result.stderr)
        self.assertEqual(self.calls(), [])

    # remove

    def test_remove_dry_run_changes_nothing(self) -> None:
        self.add_feature()
        result = self.run_cli("remove", "--host", "app", "--workspace", "sp2", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("would remove jj workspace feature", result.stdout)
        self.assertTrue(self.workspace.is_dir())
        self.assertEqual(self.calls(), ["herdr-app ls", "hc get t2 --json"])

    def test_remove_deletes_workspace_and_closes_its_space(self) -> None:
        self.add_feature()
        result = self.run_cli("remove", "--host", "app", "--workspace", "sp2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("removed jj workspace feature", result.stdout)
        self.assertFalse(self.workspace.exists())
        self.assertEqual(self.workspace_names(), ["default"])
        self.assertEqual(
            self.calls(),
            ["herdr-app ls", "hc get t2 --json", 'herdr-app do space.close {"id": "sp2", "confirmed": true}'],
        )

    def test_remove_defaults_to_the_calling_terminal_space(self) -> None:
        self.add_feature()
        result = self.run_cli("remove", "--host", "app", "--dry-run", HC_TERMINAL_ID="t2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["hc get t2 --json", "herdr-app ls", "hc get t2 --json"])

    def test_remove_with_focus_shows_primary_checkout_space(self) -> None:
        self.add_feature()
        result = self.run_cli("remove", "--host", "app", "--workspace", "sp2", "--focus")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.calls(),
            [
                "herdr-app ls",
                "hc get t2 --json",
                "herdr-app ls",
                "hc get t1 --json",
                'herdr-app do space.close {"id": "sp2", "confirmed": true}',
                'herdr-app do space.select {"id": "sp1"}',
            ],
        )

    def test_remove_with_focus_shows_space_now_in_primary_checkout(self) -> None:
        self.add_feature()
        plain = self.root / "plain"
        plain.mkdir()
        # sp3 was made in the primary checkout but has left it; sp4 was made
        # elsewhere and has since moved into it.
        self.set_world(
            app_space("sp3", self.repo, "t3"),
            app_space("sp2", self.workspace, "t2"),
            app_space("sp4", plain, "t4"),
        )
        self.set_record(terminal_record("t3", self.repo, plain, "sp3"))
        self.set_record(terminal_record("t4", plain, self.repo / "src", "sp4"))

        result = self.run_cli("remove", "--host", "app", "--workspace", "sp2", "--focus")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.calls()[2:],
            [
                "herdr-app ls",
                "hc get t3 --json",
                "hc get t2 --json",
                "hc get t4 --json",
                'herdr-app do space.close {"id": "sp2", "confirmed": true}',
                'herdr-app do space.select {"id": "sp4"}',
            ],
        )

    def test_remove_refuses_primary_checkout(self) -> None:
        result = self.run_cli("remove", "--host", "app", "--workspace", "sp1")
        self.assertEqual(result.returncode, 1)
        self.assertIn(f"{self.repo} is not a removable jj workspace", result.stderr)
        self.assertTrue((self.repo / ".jj").is_dir())
        self.assertEqual(self.calls(), ["herdr-app ls", "hc get t1 --json"])

    def test_remove_refuses_plain_git_worktree(self) -> None:
        worktree = self.root / "git-worktree"
        _ = subprocess.run(
            ["git", "-C", str(self.repo), "worktree", "add", "-q", str(worktree)],
            env=self.env,
            check=True,
            capture_output=True,
        )
        self.set_record(terminal_record("t2", worktree, worktree, "sp2"))
        result = self.run_cli("remove", "--host", "app", "--workspace", "sp2")
        self.assertEqual(result.returncode, 1)
        self.assertIn(f"{worktree} is not a removable jj workspace", result.stderr)
        self.assertTrue(worktree.is_dir())

    def test_remove_refuses_unknown_space(self) -> None:
        result = self.run_cli("remove", "--host", "app", "--workspace", "sp5")
        self.assertEqual(result.returncode, 1)
        self.assertIn("the Herdr app has no space sp5", result.stderr)

    def test_remove_outside_app_pane_needs_workspace(self) -> None:
        result = self.run_cli("remove", "--host", "app", HC_TERMINAL_ID="")
        self.assertEqual(result.returncode, 1)
        self.assertIn("pass --workspace", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_remove_reports_space_the_app_could_not_close(self) -> None:
        self.add_feature()
        result = self.run_cli(
            "remove", "--host", "app", "--workspace", "sp2", APP_STUB_FAIL_DO="space.close", APP_STUB_ERROR="busy"
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("removed the jj workspace, but the Herdr app could not close space sp2", result.stderr)
        self.assertIn("busy", result.stderr)
        self.assertFalse(self.workspace.exists())

    def test_remove_reports_hc_failure(self) -> None:
        (self.records / "t2.json").unlink()
        result = self.run_cli("remove", "--host", "app", "--workspace", "sp2")
        self.assertEqual(result.returncode, 1)
        self.assertIn("hc get t2 --json failed: no terminal t2", result.stderr)

    # Popups

    def test_prompt_add_creates_and_shows_new_space(self) -> None:
        result = self.run_cli("prompt-add", "--host", "app", stdin="feature\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("New jj workspace for repo", result.stdout)
        self.assertLess(result.stdout.index("Base: trunk()"), result.stdout.index("Name: "))
        self.assertEqual(self.workspace_names(), ["default", "feature"])
        self.assertEqual(
            self.calls(), ["herdr-app ls", f'herdr-app do space.new {{"folder": "{self.workspace}"}}']
        )
        # Without bookmarks there is no base to choose, so fzf never runs.
        self.assertFalse(self.fzf_base_input.exists())
        self.assertEqual(self.commit("feature@-"), self.commit("trunk()"))

    def test_prompt_add_invalid_name_after_base_creates_nothing(self) -> None:
        self.create_bookmarks_to_stack_on()
        result = self.run_cli("prompt-add", "--host", "app", stdin="../escape\n\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("one path component", result.stderr)
        self.assertIn("Press enter to close.", result.stderr)
        self.assertTrue(self.fzf_base_input.exists())
        self.assertEqual(self.workspace_names(), ["default"])
        self.assertEqual(self.calls(), [])

    def test_prompt_add_base_enter_keeps_trunk(self) -> None:
        self.create_bookmarks_to_stack_on()
        result = self.run_cli("prompt-add", "--host", "app", stdin="feature\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(result.stdout.index("Base: trunk()"), result.stdout.index("Name: "))
        self.assertEqual(
            self.fzf_base_input.read_text().splitlines(),
            [
                "trunk()",
                f"newer \t{self.change_id('newer')} \tlater",
                f"base  \t{self.change_id('base')} \tinitial",
            ],
        )
        # Only the bookmark name, the first tab-separated field, is searched,
        # and the listed order breaks ties between equal matches.
        self.assertEqual(
            self.fzf_base_arguments.read_text().splitlines(),
            ["--prompt=Base revision> ", "--delimiter=\t", "--nth=1", "--tiebreak=index", "--tabstop=1"],
        )
        self.assertEqual(self.commit("feature@-"), self.commit("trunk()"))

    def test_prompt_add_base_bookmark_starts_on_it(self) -> None:
        self.create_bookmarks_to_stack_on()
        result = self.run_cli("prompt-add", "--host", "app", stdin="feature\n", FAKE_FZF_BASE_CHOICE="3")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"Base: base  {self.change_id('base')}  initial\n", result.stdout)
        self.assertEqual(self.commit("feature@-"), self.commit("base"))
        self.assertEqual(self.calls()[-1], f'herdr-app do space.new {{"folder": "{self.workspace}"}}')

    def test_prompt_add_base_closed_without_choosing_creates_nothing(self) -> None:
        self.create_bookmarks_to_stack_on()
        for status in ("1", "130"):
            with self.subTest(status=status):
                result = self.run_cli("prompt-add", "--host", "app", stdin="", FAKE_FZF_BASE_STATUS=status)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("Name: ", result.stdout)
                self.assertEqual(self.workspace_names(), ["default"])
                self.assertFalse(self.workspace.exists())
                self.assertEqual(self.calls(), [])

    def test_prompt_add_base_fzf_failure_waits_for_enter(self) -> None:
        self.create_bookmarks_to_stack_on()
        result = self.run_cli("prompt-add", "--host", "app", stdin="\n", FAKE_FZF_BASE_STATUS="2")
        self.assertEqual(result.returncode, 1)
        self.assertIn("fzf exited with status 2", result.stderr)
        self.assertIn("Press enter to close.", result.stderr)
        self.assertEqual(self.workspace_names(), ["default"])

    def test_prompt_add_base_leaves_out_deleted_bookmarks(self) -> None:
        # A bookmark deleted locally but still on a tracked remote stays listed by jj as deleted.
        remote = self.root / "remote.git"
        _ = subprocess.run(["git", "init", "--bare", str(remote)], env=self.env, check=True, capture_output=True)
        _ = self.jj("git", "remote", "add", "origin", str(remote))
        _ = self.jj("bookmark", "create", "gone", "kept", "-r", "@-")
        _ = self.jj("git", "push", "--bookmark", "gone")
        _ = self.jj("bookmark", "delete", "gone")

        result = self.run_cli("prompt-add", "--host", "app", stdin="feature\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.fzf_base_input.read_text().splitlines(),
            ["trunk()", f"kept \t{self.change_id('kept')} \tinitial"],
        )

    def test_prompt_add_base_leaves_out_bookmarks_in_trunk(self) -> None:
        self.push_main_as_trunk()
        self.create_bookmarks_to_stack_on()

        result = self.run_cli("prompt-add", "--host", "app", stdin="feature\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        # trunk() covers main and base, which share its commit, so only newer is listed after it.
        self.assertEqual(
            self.fzf_base_input.read_text().splitlines(),
            ["trunk()", f"newer \t{self.change_id('newer')} \tlater"],
        )

    def test_prompt_add_base_lists_description_holding_line_separator(self) -> None:
        self.create_bookmark_described("odd", "fix\u2028thing")
        result = self.run_cli("prompt-add", "--host", "app", stdin="feature\n", FAKE_FZF_BASE_CHOICE="2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.base_rows(), ["trunk()", f"odd \t{self.change_id('odd')} \tfix\u2028thing"])
        self.assertIn(f"Base: odd  {self.change_id('odd')}  fix\u2028thing\n", result.stdout)
        self.assertEqual(self.commit("feature@-"), self.commit("odd"))

    def test_prompt_add_base_malformed_bookmark_row_fails_without_fzf(self) -> None:
        # jj keeps the lone carriage return in the first line, and Python's
        # text decoding turns it into a newline that splits the bookmark's row,
        # leaving "thing" a row of its own.
        self.create_bookmark_described("odd", "fix\rthing")
        result = self.run_cli("prompt-add", "--host", "app", stdin="\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("jj bookmark list printed malformed row 'thing'", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertIn("Press enter to close.", result.stderr)
        self.assertFalse(self.fzf_base_input.exists())
        self.assertEqual(self.workspace_names(), ["default"])

    def test_prompt_add_base_with_every_bookmark_in_trunk_starts_on_trunk(self) -> None:
        self.push_main_as_trunk()
        _ = self.jj("bookmark", "create", "old", "-r", "@-")

        result = self.run_cli("prompt-add", "--host", "app", stdin="feature\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Base: trunk()", result.stdout)
        self.assertFalse(self.fzf_base_input.exists())
        self.assertEqual(self.commit("feature@-"), self.commit("main"))

    def base_rows(self) -> list[str]:
        # Split on newlines alone, as fzf does, so a row holding U+2028 stays whole.
        return self.fzf_base_input.read_text().split("\n")[:-1]

    def picked_rows(self) -> list[str]:
        # Split on newlines alone, as fzf does, so a row holding U+2028 stays whole.
        return self.fzf_input.read_text().split("\n")[:-1]

    def add_listed_repository(self, name: str) -> Path:
        """Make ~/NAME, a jj repository with bookmark elsewhere on a commit described "other work"."""
        repository = self.root / "home" / name
        _ = subprocess.run(["jj", "git", "init", str(repository)], env=self.env, check=True, capture_output=True)
        _ = subprocess.run(
            ["jj", "-R", str(repository), "commit", "-m", "other work"], env=self.env, check=True, capture_output=True
        )
        _ = subprocess.run(
            ["jj", "-R", str(repository), "bookmark", "create", "elsewhere", "-r", "@-"],
            env=self.env,
            check=True,
            capture_output=True,
        )
        return repository

    def add_failing_repository(self, name: str) -> Path:
        """Make ~/NAME, whose bare .jj directory counts as a primary checkout but makes jj fail."""
        repository = self.root / "home" / name
        (repository / ".jj").mkdir(parents=True)
        return repository

    def assert_unlisted_row(self, row: str, label: str) -> None:
        """Assert ROW is LABEL's only row: trunk() with why its bookmarks are not listed."""
        self.assertRegex(row, rf"^{label} *\ttrunk\(\) \t\(bookmarks not listed: ")

    def test_prompt_add_pick_enter_picks_first_repository_on_trunk(self) -> None:
        self.create_bookmarks_to_stack_on()
        result = self.run_cli("prompt-add", "--host", "app", "--pick", stdin="feature\n", FAKE_FZF_CHOICE="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.picked_rows(),
            [
                f"{self.repo} \ttrunk()",
                f"{self.repo} \tnewer \t{self.change_id('newer')} \tlater",
                f"{self.repo} \tbase  \t{self.change_id('base')} \tinitial",
            ],
        )
        # Only the repository and bookmark name, the first two tab-separated
        # fields, are searched, and the listed order breaks ties.
        self.assertEqual(
            self.fzf_arguments.read_text().splitlines(),
            ["--prompt=New jj workspace> ", "--delimiter=\t", "--nth=1,2", "--tiebreak=index", "--tabstop=1"],
        )
        self.assertIn("New jj workspace for repo", result.stdout)
        self.assertLess(result.stdout.index("Base: trunk()\n"), result.stdout.index("Name: "))
        self.assertEqual(self.commit("feature@-"), self.commit("trunk()"))

    def test_prompt_add_pick_bookmark_starts_on_it_without_a_base_picker(self) -> None:
        self.create_bookmarks_to_stack_on()
        result = self.run_cli("prompt-add", "--host", "app", "--pick", stdin="feature\n", FAKE_FZF_CHOICE="2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("New jj workspace for repo", result.stdout)
        self.assertIn(f"Base: newer  {self.change_id('newer')}  later\n", result.stdout)
        self.assertFalse(self.fzf_base_input.exists())
        self.assertEqual(self.commit("feature@-"), self.commit("newer"))
        self.assertEqual(self.calls()[-1], f'herdr-app do space.new {{"folder": "{self.workspace}"}}')

    def test_prompt_add_pick_leaves_out_bookmarks_in_trunk(self) -> None:
        self.push_main_as_trunk()
        self.create_bookmarks_to_stack_on()
        result = self.run_cli("prompt-add", "--host", "app", "--pick")
        self.assertEqual(result.returncode, 0, result.stderr)
        # trunk() covers main and base, which share its commit.
        self.assertEqual(
            self.picked_rows(),
            [f"{self.repo} \ttrunk()", f"{self.repo} \tnewer \t{self.change_id('newer')} \tlater"],
        )

    def test_prompt_add_pick_lists_each_local_jj_repository_once(self) -> None:
        self.add_feature()
        plain = self.root / "plain"
        plain.mkdir()
        other = self.add_failing_repository("other")
        remote = self.add_failing_repository("remote")
        unplaced = app_space("sp6", plain, "t6")
        unplaced["folder"] = ""
        unplaced["tabs"] = list[object]()
        on_other_machine = app_space("sp5", remote, "t5")
        on_other_machine["machine"] = "m1"
        self.set_world(
            app_space("sp2", self.workspace, "t2"),
            app_space("sp3", plain, "t3"),
            app_space("sp4", other, "t4"),
            app_space("sp1", self.repo, "t1", shown=True),
            on_other_machine,
            unplaced,
        )
        self.set_record(terminal_record("t3", plain, plain, "sp3"))
        self.set_record(terminal_record("t4", other, other, "sp4"))

        result = self.run_cli("prompt-add", "--host", "app", "--pick", stdin="second\n", FAKE_FZF_CHOICE="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = self.picked_rows()
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0], f"{self.repo} \ttrunk()")
        self.assert_unlisted_row(rows[1], "~/other")
        self.assertIn("New jj workspace for repo", result.stdout)
        second = self.workspace.parent / "second"
        self.assertEqual(self.workspace_names(), ["default", "feature", "second"])
        self.assertEqual(
            self.calls(),
            [
                "herdr-app ls",
                "hc get t2 --json",
                "hc get t3 --json",
                "hc get t4 --json",
                "hc get t1 --json",
                "herdr-app ls",
                f'herdr-app do space.new {{"folder": "{second}"}}',
            ],
        )

    def test_prompt_add_pick_lists_repositories_spaces_are_now_in(self) -> None:
        plain = self.root / "plain"
        plain.mkdir()
        other = self.add_failing_repository("other")
        # sp3 was made outside any repository and has since moved into other;
        # sp1 was made in the primary checkout and has since left it.
        self.set_world(
            app_space("sp3", plain, "t3"),
            app_space("sp1", self.repo, "t1", shown=True),
        )
        self.set_record(terminal_record("t3", plain, other, "sp3"))
        self.set_record(terminal_record("t1", self.repo, plain, "sp1"))

        result = self.run_cli("prompt-add", "--host", "app", "--pick")
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = self.picked_rows()
        self.assertEqual(len(rows), 1)
        self.assert_unlisted_row(rows[0], "~/other")

    def test_prompt_add_pick_repository_whose_bookmarks_fail_can_be_picked_on_trunk(self) -> None:
        other = self.add_failing_repository("other")
        self.set_world(app_space("sp4", other, "t4", shown=True))
        self.set_record(terminal_record("t4", other, other, "sp4"))

        result = self.run_cli("prompt-add", "--host", "app", "--pick", stdin="second\n\n", FAKE_FZF_CHOICE="1")
        # The stand-in repository has no store, so creating the workspace fails
        # after the pick, which the name prompt shows went through.
        self.assertIn("New jj workspace for other\nBase: trunk()\n", result.stdout)
        self.assertEqual(self.workspace_names(), ["default"])

    def test_prompt_add_pick_lists_description_holding_line_separator(self) -> None:
        self.create_bookmark_described("odd", "fix\u2028thing\n\nbody")
        second = self.add_listed_repository("second")
        self.set_world(
            app_space("sp1", self.repo, "t1", shown=True),
            app_space("sp4", second, "t4"),
        )
        self.set_record(terminal_record("t4", second, second, "sp4"))

        result = self.run_cli("prompt-add", "--host", "app", "--pick", stdin="feature\n", FAKE_FZF_CHOICE="2")
        self.assertEqual(result.returncode, 0, result.stderr)
        second_label = f"{'~/second':<{len(str(self.repo))}}"
        elsewhere = subprocess.run(
            ["jj", "-R", str(second), "log", "--no-graph", "-r", "elsewhere", "-T", "change_id.shortest(8)"],
            env=self.env,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        self.assertEqual(
            self.picked_rows(),
            [
                f"{self.repo} \ttrunk()",
                f"{self.repo} \todd \t{self.change_id('odd')} \tfix\u2028thing",
                f"{second_label} \ttrunk()",
                f"{second_label} \telsewhere \t{elsewhere} \tother work",
            ],
        )
        self.assertIn(f"Base: odd  {self.change_id('odd')}  fix\u2028thing\n", result.stdout)
        self.assertEqual(self.commit("feature@-"), self.commit("odd"))

    def test_prompt_add_pick_malformed_bookmark_row_keeps_later_repositories(self) -> None:
        # jj keeps the lone carriage return in the first line, and Python's
        # text decoding turns it into a newline that splits the bookmark's row,
        # leaving "thing" a row of its own.
        self.create_bookmark_described("odd", "fix\rthing")
        second = self.add_listed_repository("second")
        self.set_world(
            app_space("sp1", self.repo, "t1", shown=True),
            app_space("sp4", second, "t4"),
        )
        self.set_record(terminal_record("t4", second, second, "sp4"))

        result = self.run_cli("prompt-add", "--host", "app", "--pick")
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = self.picked_rows()
        self.assertEqual(len(rows), 3)
        self.assert_unlisted_row(rows[0], re.escape(str(self.repo)))
        self.assertIn("jj bookmark list printed malformed row 'thing'", rows[0])
        second_label = f"{'~/second':<{len(str(self.repo))}}"
        self.assertEqual(rows[1], f"{second_label} \ttrunk()")
        self.assertRegex(rows[2], rf"^{re.escape(second_label)} \telsewhere \t\w+ \tother work$")

    def test_prompt_add_pick_closed_without_choosing_creates_nothing(self) -> None:
        for status in ("1", "130"):
            with self.subTest(status=status):
                result = self.run_cli("prompt-add", "--host", "app", "--pick", FAKE_FZF_STATUS=status)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.picked_rows(), [f"{self.repo} \ttrunk()"])
                self.assertNotIn("Name: ", result.stdout)
                self.assertEqual(self.workspace_names(), ["default"])
                self.assertEqual(self.calls(), ["herdr-app ls", "hc get t1 --json", "hc get t2 --json"])

    def test_prompt_add_pick_choice_before_every_repository_is_listed_creates_it(self) -> None:
        self.create_bookmarks_to_stack_on()
        other = self.add_failing_repository("other")
        third = self.add_failing_repository("third")
        self.set_world(
            app_space("sp1", self.repo, "t1", shown=True),
            app_space("sp4", other, "t4"),
            app_space("sp5", third, "t5"),
        )
        self.set_record(terminal_record("t4", other, other, "sp4"))
        self.set_record(terminal_record("t5", third, third, "sp5"))

        result = self.run_cli("prompt-add", "--host", "app", "--pick", stdin="feature\n", FAKE_FZF_EARLY_EXIT="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("New jj workspace for repo\nBase: trunk()\n", result.stdout)
        self.assertEqual(self.commit("feature@-"), self.commit("trunk()"))

    def test_prompt_add_pick_opens_fzf_once_the_first_repository_is_listed(self) -> None:
        # fzf takes Enter on an empty list as no match, so the first
        # repository's rows must already be ready when fzf opens.
        self.create_bookmarks_to_stack_on()
        other = self.add_failing_repository("other")
        self.set_world(app_space("sp1", self.repo, "t1", shown=True), app_space("sp4", other, "t4"))
        self.set_record(terminal_record("t4", other, other, "sp4"))
        events = self.root / "events.log"
        self.hold_back_jj(self.repo, events)

        result = self.run_cli(
            "prompt-add", "--host", "app", "--pick", stdin="feature\n", FAKE_FZF_EARLY_EXIT="1", EVENT_LOG=str(events)
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(events.read_text().splitlines(), ["jj listing", "jj released", "fzf started"])
        self.assertIn("New jj workspace for repo\nBase: trunk()\n", result.stdout)

    def test_prompt_add_pick_opens_fzf_while_later_repositories_are_listed(self) -> None:
        # One slow repository must not hold the picker back for the others:
        # second's listing starts before fzf opens and finishes only after.
        self.create_bookmarks_to_stack_on()
        second = self.add_listed_repository("second")
        self.set_world(app_space("sp1", self.repo, "t1", shown=True), app_space("sp4", second, "t4"))
        self.set_record(terminal_record("t4", second, second, "sp4"))
        events = self.root / "events.log"
        self.hold_back_jj(second, events, label="second jj", release_after="fzf started")
        self.hold_back_jj(self.repo, events, release_after="second jj listing")

        result = self.run_cli(
            "prompt-add", "--host", "app", "--pick", stdin="feature\n", FAKE_FZF_EARLY_EXIT="1", EVENT_LOG=str(events)
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        # Both listings start at once, so either may log "listing" first, and
        # second is released only after fzf started, when the CLI may be done.
        events_until_fzf = events.read_text().split("fzf started\n")[0].splitlines()
        self.assertEqual(
            [event for event in events_until_fzf if event != "jj listing"], ["second jj listing", "jj released"]
        )
        self.assertIn("New jj workspace for repo\nBase: trunk()\n", result.stdout)
        self.assertEqual(self.commit("feature@-"), self.commit("trunk()"))

    def hold_back_jj(
        self, repository: Path, events: Path, *, label: str = "jj", release_after: str | None = None
    ) -> None:
        """Make the next jj command in REPOSITORY wait until it is released, logging its progress to EVENTS.

        "LABEL listing" is appended once jj waits, and "LABEL released" just
        before it is released: once RELEASE_AFTER is a line of EVENTS or, with
        none, a second after it began waiting. Each wait gives up after ten
        seconds, so a test whose expected event never comes fails on the event
        order instead of hanging.

        jj reads the repository's store type when it loads the repository, so
        that file becomes a FIFO, which jj cannot open until it is opened for
        writing. Once jj has it open, the regular file is put back for later
        jj commands, and jj reads the type through the FIFO.
        """
        store_type = repository / ".jj" / "repo" / "store" / "type"
        content = store_type.read_text()
        held_type = self.root / f"held-store-type-{repository.name}"
        _ = held_type.write_text(content)
        store_type.unlink()
        os.mkfifo(store_type)

        def log(event: str) -> None:
            with events.open("a") as event_log:
                _ = event_log.write(f"{event}\n")

        def logged(event: str) -> bool:
            try:
                return event in events.read_text().splitlines()
            except FileNotFoundError:
                return False

        def release() -> None:
            # Opening the FIFO without blocking fails with ENXIO until jj has it open for reading.
            deadline = time.monotonic() + 10
            while True:
                try:
                    fifo = os.open(store_type, os.O_WRONLY | os.O_NONBLOCK)
                    break
                except OSError as error:
                    if error.errno != errno.ENXIO or time.monotonic() > deadline:
                        return
                    time.sleep(0.01)
            _ = held_type.replace(store_type)
            log(f"{label} listing")

            if release_after is None:
                time.sleep(1)
            else:
                deadline = time.monotonic() + 10
                while not logged(release_after) and time.monotonic() < deadline:
                    time.sleep(0.01)
            log(f"{label} released")

            # jj may already be killed, once fzf has exited.
            try:
                _ = os.write(fifo, content.encode())
            except OSError:
                pass
            finally:
                os.close(fifo)

        threading.Thread(target=release, daemon=True).start()

    def test_prompt_add_pick_fzf_failure_waits_for_enter(self) -> None:
        result = self.run_cli("prompt-add", "--host", "app", "--pick", stdin="\n", FAKE_FZF_STATUS="2")
        self.assertEqual(result.returncode, 1)
        self.assertIn("fzf exited with status 2", result.stderr)
        self.assertIn("Press enter to close.", result.stderr)
        self.assertEqual(self.workspace_names(), ["default"])

    def test_prompt_add_pick_without_jj_spaces_fails_before_fzf(self) -> None:
        plain = self.root / "plain"
        plain.mkdir()
        self.set_world(app_space("sp3", plain, "t3", shown=True))
        self.set_record(terminal_record("t3", plain, plain, "sp3"))
        result = self.run_cli("prompt-add", "--host", "app", "--pick", stdin="\n", FAKE_FZF_CHOICE="1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("no space on this machine is in a jj repository; run jjx ensure", result.stderr)
        self.assertIn("Press enter to close.", result.stderr)
        self.assertFalse(self.fzf_arguments.exists())

    def test_prompt_add_pick_needs_app_host(self) -> None:
        result = self.run_cli(
            "prompt-add", "--host", "tui", "--pick", stdin="\n", HERDR_PLUGIN_CONTEXT_JSON='{"workspace_id": "w1"}'
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("--pick needs the app host", result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertFalse(self.fzf_arguments.exists())

    def test_prompt_add_pick_lists_first_folders_repository_first(self) -> None:
        self.create_bookmarks_to_stack_on()
        other = self.add_failing_repository("other")
        third = self.add_failing_repository("third")
        (third / "sub").mkdir()
        self.set_world(
            app_space("sp1", self.repo, "t1", shown=True),
            app_space("sp4", other, "t4"),
        )
        self.set_record(terminal_record("t4", other, other, "sp4"))
        without_first = self.run_cli("prompt-add", "--host", "app", "--pick")
        self.assertEqual(without_first.returncode, 0, without_first.stderr)
        calls_without_first = self.calls()

        result = self.run_cli("prompt-add", "--host", "app", "--pick", "--first", str(third / "sub"))
        self.assertEqual(result.returncode, 0, result.stderr)
        # Each repository's rows are contiguous: ~/third's, then the sidebar's in order.
        rows = self.picked_rows()
        self.assertEqual(len(rows), 5)
        self.assert_unlisted_row(rows[0], "~/third")
        self.assertEqual(
            rows[1:4],
            [
                f"{self.repo} \ttrunk()",
                f"{self.repo} \tnewer \t{self.change_id('newer')} \tlater",
                f"{self.repo} \tbase  \t{self.change_id('base')} \tinitial",
            ],
        )
        self.assert_unlisted_row(rows[4], "~/other")
        self.assertEqual(self.calls(), calls_without_first)

    def test_prompt_add_pick_first_enter_picks_its_repository_once(self) -> None:
        self.add_feature()
        other = self.add_failing_repository("other")
        self.set_world(
            app_space("sp4", other, "t4"),
            app_space("sp1", self.repo, "t1", shown=True),
            app_space("sp2", self.workspace, "t2"),
        )
        self.set_record(terminal_record("t4", other, other, "sp4"))

        result = self.run_cli(
            "prompt-add",
            "--host",
            "app",
            "--pick",
            "--first",
            str(self.workspace),
            stdin="second\n",
            FAKE_FZF_CHOICE="1",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = self.picked_rows()
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0], f"{self.repo} \ttrunk()")
        self.assert_unlisted_row(rows[1], "~/other")
        second = self.workspace.parent / "second"
        self.assertEqual(self.workspace_names(), ["default", "feature", "second"])
        self.assertEqual(self.calls()[-1], f'herdr-app do space.new {{"folder": "{second}"}}')

    def test_prompt_add_pick_first_outside_repository_lists_as_before(self) -> None:
        plain = self.root / "plain"
        plain.mkdir()
        without_first = self.run_cli("prompt-add", "--host", "app", "--pick")
        self.assertEqual(without_first.returncode, 0, without_first.stderr)
        listed_without_first = self.picked_rows()

        for first in (plain, plain / "gone"):
            with self.subTest(first=first.name):
                result = self.run_cli("prompt-add", "--host", "app", "--pick", "--first", str(first))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.picked_rows(), listed_without_first)

    def test_prompt_add_pick_first_without_jj_spaces_still_lists_it(self) -> None:
        plain = self.root / "plain"
        plain.mkdir()
        self.set_world(app_space("sp3", plain, "t3", shown=True))
        self.set_record(terminal_record("t3", plain, plain, "sp3"))

        result = self.run_cli("prompt-add", "--host", "app", "--pick", "--first", str(self.repo / "src"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.picked_rows(), [f"{self.repo} \ttrunk()"])

    def test_prompt_add_first_needs_pick(self) -> None:
        result = self.run_cli("prompt-add", "--host", "app", "--first", str(self.repo), stdin="\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("--first needs --pick", result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertFalse(self.fzf_arguments.exists())

    def test_prompt_remove_declined_changes_nothing(self) -> None:
        self.add_feature()
        result = self.run_cli("prompt-remove", "--host", "app", "--workspace", "sp2", stdin="n\n", HC_TERMINAL_ID="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("closes its Herdr app space", result.stdout)
        self.assertTrue(self.workspace.is_dir())
        self.assertEqual(self.calls(), ["herdr-app ls", "hc get t2 --json"])

    def test_prompt_remove_confirmed_removes_and_shows_primary_space(self) -> None:
        self.add_feature()
        result = self.run_cli("prompt-remove", "--host", "app", "--workspace", "sp2", stdin="y\n", HC_TERMINAL_ID="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.workspace.exists())
        self.assertEqual(
            self.calls()[-2:],
            ['herdr-app do space.close {"id": "sp2", "confirmed": true}', 'herdr-app do space.select {"id": "sp1"}'],
        )

    def test_prompt_remove_refusal_waits_for_enter(self) -> None:
        result = self.run_cli("prompt-remove", "--host", "app", "--workspace", "sp1", stdin="\n", HC_TERMINAL_ID="")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not a removable jj workspace", result.stderr)
        self.assertIn("Press enter to close.", result.stderr)
        self.assertTrue((self.repo / ".jj").is_dir())


if __name__ == "__main__":
    _ = unittest.main()
