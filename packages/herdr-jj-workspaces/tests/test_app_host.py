"""herdr-jj-workspace driving the Herdr desktop app (--host app) through fake herdr-app and hc executables."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
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

# fzf, named by $HERDR_JJ_WORKSPACE_FZF_PATH: records its input lines in
# $FAKE_FZF_INPUT, then prints input line $FAKE_FZF_CHOICE and exits 0, or, with
# no choice, exits 130 as fzf does on Esc; $FAKE_FZF_STATUS overrides the status.
FAKE_FZF = """\
#!/bin/sh
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
        self.assertEqual(self.workspace_names(), ["default", "feature"])
        self.assertEqual(
            self.calls(), ["herdr-app ls", f'herdr-app do space.new {{"folder": "{self.workspace}"}}']
        )

    def test_prompt_add_error_waits_for_enter(self) -> None:
        result = self.run_cli("prompt-add", "--host", "app", stdin="../escape\n\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Press enter to close.", result.stderr)
        self.assertEqual(self.workspace_names(), ["default"])

    def test_prompt_add_pick_lists_each_local_jj_repository_once(self) -> None:
        self.add_feature()
        plain = self.root / "plain"
        plain.mkdir()
        # find_jj_checkout needs only a .jj directory to count a folder as a primary checkout.
        other = self.root / "home" / "other"
        remote = self.root / "home" / "remote"
        for repository in (other, remote):
            (repository / ".jj").mkdir(parents=True)
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
        self.assertEqual(self.fzf_input.read_text().splitlines(), [str(self.repo), "~/other"])
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
        other = self.root / "home" / "other"
        (other / ".jj").mkdir(parents=True)
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
        self.assertEqual(self.fzf_input.read_text().splitlines(), ["~/other"])

    def test_prompt_add_pick_closed_without_choosing_creates_nothing(self) -> None:
        for status in ("1", "130"):
            with self.subTest(status=status):
                result = self.run_cli("prompt-add", "--host", "app", "--pick", FAKE_FZF_STATUS=status)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.fzf_input.read_text().splitlines(), [str(self.repo)])
                self.assertEqual(self.workspace_names(), ["default"])
                self.assertEqual(self.calls(), ["herdr-app ls", "hc get t1 --json", "hc get t2 --json"])

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
        self.assertFalse(self.fzf_input.exists())

    def test_prompt_add_pick_needs_app_host(self) -> None:
        result = self.run_cli(
            "prompt-add", "--host", "tui", "--pick", stdin="\n", HERDR_PLUGIN_CONTEXT_JSON='{"workspace_id": "w1"}'
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("--pick needs the app host", result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertFalse(self.fzf_input.exists())

    def test_prompt_add_pick_lists_first_folders_repository_first(self) -> None:
        other = self.root / "home" / "other"
        third = self.root / "home" / "third"
        for repository in (other, third):
            (repository / ".jj").mkdir(parents=True)
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
        self.assertEqual(self.fzf_input.read_text().splitlines(), ["~/third", str(self.repo), "~/other"])
        self.assertEqual(self.calls(), calls_without_first)

    def test_prompt_add_pick_first_enter_picks_its_repository_once(self) -> None:
        self.add_feature()
        other = self.root / "home" / "other"
        (other / ".jj").mkdir(parents=True)
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
        self.assertEqual(self.fzf_input.read_text().splitlines(), [str(self.repo), "~/other"])
        second = self.workspace.parent / "second"
        self.assertEqual(self.workspace_names(), ["default", "feature", "second"])
        self.assertEqual(self.calls()[-1], f'herdr-app do space.new {{"folder": "{second}"}}')

    def test_prompt_add_pick_first_outside_repository_lists_as_before(self) -> None:
        plain = self.root / "plain"
        plain.mkdir()
        without_first = self.run_cli("prompt-add", "--host", "app", "--pick")
        self.assertEqual(without_first.returncode, 0, without_first.stderr)
        listed_without_first = self.fzf_input.read_text().splitlines()

        for first in (plain, plain / "gone"):
            with self.subTest(first=first.name):
                result = self.run_cli("prompt-add", "--host", "app", "--pick", "--first", str(first))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.fzf_input.read_text().splitlines(), listed_without_first)

    def test_prompt_add_pick_first_without_jj_spaces_still_lists_it(self) -> None:
        plain = self.root / "plain"
        plain.mkdir()
        self.set_world(app_space("sp3", plain, "t3", shown=True))
        self.set_record(terminal_record("t3", plain, plain, "sp3"))

        result = self.run_cli("prompt-add", "--host", "app", "--pick", "--first", str(self.repo / "src"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.fzf_input.read_text().splitlines(), [str(self.repo)])

    def test_prompt_add_first_needs_pick(self) -> None:
        result = self.run_cli("prompt-add", "--host", "app", "--first", str(self.repo), stdin="\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("--first needs --pick", result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertFalse(self.fzf_input.exists())

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
