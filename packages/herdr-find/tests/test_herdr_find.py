from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import final, override

CLI = os.environ["HERDR_FIND"]

PICKER_KEY_HINTS = "ctrl-a agents  ctrl-w workspaces  ctrl-r refresh  ctrl-o preview  ctrl-u/ctrl-d scroll preview"

# Records each call, one per line, and answers agent, workspace, tab, and pane
# list with $HERDR_STUB_AGENTS, $HERDR_STUB_WORKSPACES, $HERDR_STUB_TABS, and
# $HERDR_STUB_PANES, each a JSON list placed under the reply's result, ignoring
# any --workspace filter; agent read prints $HERDR_STUB_AGENT_OUTPUT; agent
# focus, workspace focus, and plugin pane open succeed. The call
# named by $HERDR_STUB_FAIL, such as "agent list", fails as Herdr does, writing
# $HERDR_STUB_ERROR (by default a plain message) to stderr.
HERDR_STUB = """\
#!/bin/sh
printf '%s\\n' "$*" >> "$HERDR_STUB_LOG"
if [ "$1 $2" = "${HERDR_STUB_FAIL:-}" ]; then
  printf '%s\\n' "${HERDR_STUB_ERROR:-herdr: server not running}" >&2
  exit 1
fi
case "$1 $2" in
  "agent list")
    printf '{"result":{"type":"agent_list","agents":%s}}\\n' "$HERDR_STUB_AGENTS" ;;
  "agent read")
    printf '%s' "$HERDR_STUB_AGENT_OUTPUT" ;;
  "workspace list")
    printf '{"result":{"type":"workspace_list","workspaces":%s}}\\n' "$HERDR_STUB_WORKSPACES" ;;
  "tab list")
    printf '{"result":{"type":"tab_list","tabs":%s}}\\n' "$HERDR_STUB_TABS" ;;
  "pane list")
    printf '{"result":{"type":"pane_list","panes":%s}}\\n' "$HERDR_STUB_PANES" ;;
  "agent focus"|"workspace focus"|"plugin pane")
    printf '{"result":{"type":"ok"}}\\n' ;;
  *)
    exit 2 ;;
esac
"""

Records = Sequence[dict[str, object]]

ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")


def agent(pane_id: str, status: str, seq: int, workspace_id: str = "w1", **fields: object) -> dict[str, object]:
    """Return an agent record shaped like one from ``herdr agent list``."""
    return {
        "agent": "claude",
        "agent_status": status,
        "cwd": "/srv/project",
        "focused": False,
        "foreground_cwd": "/srv/project",
        "pane_id": pane_id,
        "revision": 1,
        "state_change_seq": seq,
        "tab_id": f"{workspace_id}:t1",
        "terminal_title": f"◐ title {pane_id}",
        "terminal_title_stripped": f"title {pane_id}",
        "workspace_id": workspace_id,
        **fields,
    }


def workspace(workspace_id: str, number: int | None, **fields: object) -> dict[str, object]:
    """Return a workspace record shaped like one from ``herdr workspace list``."""
    return {
        "active_tab_id": f"{workspace_id}:t1",
        "agent_status": "unknown",
        "focused": False,
        "label": f"label-{workspace_id}",
        "number": number,
        "pane_count": 1,
        "tab_count": 1,
        "workspace_id": workspace_id,
        "worktree": {
            "checkout_path": f"/srv/{workspace_id}",
            "is_linked_worktree": False,
            "repo_name": workspace_id,
            "repo_root": f"/srv/{workspace_id}",
        },
        **fields,
    }


def pane(
    pane_id: str, workspace_id: str, tab_id: str, cwd: str, *, focused: bool = False, **fields: object
) -> dict[str, object]:
    """Return a pane record shaped like one from ``herdr pane list``."""
    return {
        "agent_status": "unknown",
        "cwd": cwd,
        "focused": focused,
        "pane_id": pane_id,
        "tab_id": tab_id,
        "terminal_title_stripped": "~",
        "workspace_id": workspace_id,
        **fields,
    }


def tab(tab_id: str, label: str, workspace_id: str = "w1") -> dict[str, object]:
    """Return a tab record shaped like one from ``herdr tab list``."""
    return {
        "agent_status": "unknown",
        "focused": False,
        "label": label,
        "number": 1,
        "pane_count": 1,
        "tab_id": tab_id,
        "workspace_id": workspace_id,
    }


class HerdrStubTestCase(unittest.TestCase):
    """Runs the CLI against the herdr stub in a throwaway home."""

    @override
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        self.home = self.root / "home"
        self.home.mkdir()
        stub = self.root / "herdr"
        _ = stub.write_text(HERDR_STUB)
        stub.chmod(0o755)
        self.log = self.root / "herdr.log"
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "HERDR_BIN_PATH": str(stub),
            "HERDR_STUB_LOG": str(self.log),
            "HERDR_STUB_AGENTS": "[]",
            "HERDR_STUB_WORKSPACES": "[]",
            "HERDR_STUB_TABS": "[]",
            "HERDR_STUB_PANES": "[]",
            "HERDR_STUB_AGENT_OUTPUT": "",
        }

    def run_cli(
        self,
        arguments: Sequence[str],
        fixtures: Mapping[str, Records] | None = None,
        env: Mapping[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        """Run the CLI with the stub answering from FIXTURES: agents, workspaces, tabs, or panes."""
        _ = self.log.write_text("")
        run_env = dict(self.env)
        if fixtures is not None:
            for key, records in fixtures.items():
                run_env[f"HERDR_STUB_{key.upper()}"] = json.dumps(list(records))
        if env is not None:
            run_env.update(env)
        return subprocess.run(
            [CLI, *arguments],
            env=run_env,
            text=True,
            capture_output=True,
            check=False,
        )

    def herdr_calls(self) -> list[str]:
        return self.log.read_text().splitlines()


@final
class HerdrFindRowsTests(HerdrStubTestCase):
    def run_rows(
        self,
        arguments: Sequence[str] = (),
        fixtures: Mapping[str, Records] | None = None,
        env: Mapping[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return self.run_cli(["rows", *arguments], fixtures, env)

    def rows(self, *arguments: str, **fixtures: Records) -> list[tuple[str, list[str]]]:
        """Return each printed row's target and uncoloured display cells."""
        result = self.run_rows(arguments, fixtures)
        self.assertEqual(result.returncode, 0, result.stderr)
        parsed: list[tuple[str, list[str]]] = []
        for line in result.stdout.splitlines():
            target, display = line.split("\t")
            parsed.append((target, re.split(r" {2,}", ANSI_ESCAPE.sub("", display))))
        return parsed

    def targets(self, *arguments: str, **fixtures: Records) -> list[str]:
        return [target for target, _cells in self.rows(*arguments, **fixtures)]

    def test_rows_show_agent_and_workspace_fields(self) -> None:
        home_project = str(self.home / "src" / "project")
        rows = self.rows(
            agents=[
                agent("w1:p1", "blocked", 5, cwd=home_project, agent="codex"),
                agent("w1:p2", "idle", 4),
            ],
            workspaces=[
                workspace("w1", 1, label="dotfiles", worktree={"checkout_path": str(self.home)}),
                workspace("w2", 2, label="scratch", worktree={"checkout_path": "/srv/scratch"}),
            ],
        )
        self.assertEqual(
            rows,
            [
                ("agent:w1:p1", ["blocked", "codex", "title w1:p1", "dotfiles", "~/src/project"]),
                ("agent:w1:p2", ["idle", "claude", "title w1:p2", "dotfiles", "/srv/project"]),
                ("workspace:w1", ["dotfiles", "~", "1 blocked, 1 idle"]),
                ("workspace:w2", ["scratch", "/srv/scratch", "no agents"]),
            ],
        )
        self.assertEqual(self.herdr_calls(), ["agent list", "workspace list"])

    def test_agents_sort_by_status_then_latest_change(self) -> None:
        agents = [
            agent("p-working", "working", 9),
            agent("p-unknown", "unknown", 8),
            agent("p-idle", "idle", 7),
            agent("p-novel", "thinking", 10),
            agent("p-done", "done", 6),
            agent("p-blocked-old", "blocked", 1),
            agent("p-blocked-new", "blocked", 3),
            agent("p-blocked-unsequenced", "blocked", 0, state_change_seq=None),
        ]
        self.assertEqual(
            self.targets("--only", "agents", agents=agents),
            [
                "agent:p-blocked-new",
                "agent:p-blocked-old",
                "agent:p-blocked-unsequenced",
                "agent:p-done",
                "agent:p-idle",
                "agent:p-working",
                "agent:p-novel",
                "agent:p-unknown",
            ],
        )

    def test_workspaces_sort_by_sidebar_number(self) -> None:
        workspaces = [
            workspace("w3", 3),
            workspace("w-unnumbered", None),
            workspace("w1", 1),
            workspace("w2", 2),
        ]
        self.assertEqual(
            self.targets("--only", "workspaces", workspaces=workspaces),
            ["workspace:w1", "workspace:w2", "workspace:w3", "workspace:w-unnumbered"],
        )

    def test_caller_agent_and_workspace_sort_last_in_their_groups(self) -> None:
        agents = [agent("w1:p1", "blocked", 2), agent("w2:p1", "idle", 1, workspace_id="w2")]
        workspaces = [workspace("w1", 1), workspace("w2", 2)]
        self.assertEqual(
            self.targets(agents=agents, workspaces=workspaces),
            ["agent:w1:p1", "agent:w2:p1", "workspace:w1", "workspace:w2"],
        )
        self.assertEqual(
            self.targets("--caller-workspace", "w1", "--caller-pane", "w1:p1", agents=agents, workspaces=workspaces),
            ["agent:w2:p1", "agent:w1:p1", "workspace:w2", "workspace:w1"],
        )

    def test_only_limits_rows_to_one_group(self) -> None:
        agents = [agent("w1:p1", "idle", 1)]
        workspaces = [workspace("w1", 1, label="dotfiles")]
        self.assertEqual(self.targets("--only", "agents", agents=agents, workspaces=workspaces), ["agent:w1:p1"])
        # Agent rows still show their workspace's label.
        self.assertEqual(self.rows("--only", "agents", agents=agents, workspaces=workspaces)[0][1][3], "dotfiles")
        self.assertEqual(self.targets("--only", "workspaces", agents=agents, workspaces=workspaces), ["workspace:w1"])
        self.assertEqual(
            self.rows("--only", "workspaces", agents=agents, workspaces=workspaces)[0][1][2], "1 idle"
        )

    def test_no_agents_still_lists_workspaces(self) -> None:
        self.assertEqual(
            self.rows(workspaces=[workspace("w1", 1, label="dotfiles")]),
            [("workspace:w1", ["dotfiles", "/srv/w1", "no agents"])],
        )

    def test_workspace_without_checkout_shows_a_pane_directory(self) -> None:
        workspaces = [
            workspace("w-focused", 1, worktree=None),
            workspace("w-active", 2, worktree=None),
            workspace("w-other-tab", 3, worktree=None),
            workspace("w-empty", 4, worktree=None),
        ]
        panes = [
            pane("a", "w-focused", "w-focused:t1", "/srv/active-first"),
            pane("b", "w-focused", "w-focused:t1", str(self.home / "focused"), focused=True),
            pane("c", "w-active", "w-active:t2", "/srv/inactive-tab"),
            pane("d", "w-active", "w-active:t1", "/srv/active-first"),
            pane("e", "w-active", "w-active:t1", "/srv/active-second"),
            pane("f", "w-other-tab", "w-other-tab:t2", "/srv/other-tab"),
        ]
        rows = self.rows("--only", "workspaces", workspaces=workspaces, panes=panes)
        self.assertEqual(
            [cells for _target, cells in rows],
            [
                ["label-w-focused", "~/focused", "no agents"],
                ["label-w-active", "/srv/active-first", "no agents"],
                ["label-w-other-tab", "/srv/other-tab", "no agents"],
                ["label-w-empty", "no agents"],
            ],
        )
        self.assertEqual(self.herdr_calls(), ["agent list", "workspace list", "pane list"])

    def test_missing_optional_fields_are_tolerated(self) -> None:
        rows = self.rows(agents=[{"pane_id": "p1"}], workspaces=[{"workspace_id": "w1"}])
        self.assertEqual([target for target, _cells in rows], ["agent:p1", "workspace:w1"])
        self.assertEqual(rows[0][1], ["unknown"])

    def test_control_characters_cannot_break_rows(self) -> None:
        hostile = "a\tb\nc \x1b[31mred\x1b[0m\x1b]0;title\x07\rd\x00e"
        fixtures = {
            "agents": [agent("w1:p\t1", "blocked\n", 1, terminal_title_stripped=hostile, agent="cl\x1baude")],
            "workspaces": [workspace("w1", 1, label=hostile, worktree={"checkout_path": "/srv/x\ny"})],
        }
        result = self.run_rows(fixtures=fixtures)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(len(lines), 2)
        for line in lines:
            self.assertEqual(line.count("\t"), 1, line)
            uncoloured = ANSI_ESCAPE.sub("", line)
            self.assertNotIn("\x1b", uncoloured)
            self.assertNotIn("\r", line)
            self.assertNotIn("\x00", line)
        self.assertEqual(lines[0].split("\t")[0], "agent:w1:p 1")
        self.assertIn("a b c red d e", ANSI_ESCAPE.sub("", lines[0]))
        self.assertIn("a b c red d e", ANSI_ESCAPE.sub("", lines[1]))
        self.assertIn("/srv/x y", lines[1])

    def test_herdr_failure_exits_non_zero_with_error(self) -> None:
        # The message names the call as "herdr ...", not by $HERDR_BIN_PATH,
        # here the stub's temporary path.
        for call in ("agent list", "workspace list", "pane list"):
            with self.subTest(call=call):
                result = self.run_rows(
                    fixtures={"workspaces": [workspace("w1", 1, worktree=None)]}, env={"HERDR_STUB_FAIL": call}
                )
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, f"error: herdr {call} failed: herdr: server not running\n")

    def test_malformed_herdr_reply_exits_non_zero_with_error(self) -> None:
        result = self.run_rows(env={"HERDR_STUB_AGENTS": "not json"})
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, "error: herdr agent list returned malformed JSON\n")


@final
class HerdrFindPreviewTests(HerdrStubTestCase):
    def test_agent_preview_prints_recent_output(self) -> None:
        output = "line 1\n\x1b[31mline 2\x1b[0m\n"
        result = self.run_cli(["preview", "agent:w1:p1"], env={"HERDR_STUB_AGENT_OUTPUT": output})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, output)
        self.assertEqual(self.herdr_calls(), ["agent read w1:p1 --source recent-unwrapped --lines 40"])

    def test_workspace_preview_lists_tabs_and_their_panes(self) -> None:
        tabs = [tab("w1:t1", "editor"), tab("w1:t2", ""), tab("w1:t3", "empty")]
        panes = [
            pane("w1:p1", "w1", "w1:t1", "/srv", agent="claude", agent_status="blocked", terminal_title_stripped="Fix"),
            pane("w1:p2", "w1", "w1:t2", "/srv", terminal_title_stripped="~/dotfiles"),
            pane("w1:p3", "w1", "w1:t1", "/srv", agent="codex", agent_status="working", terminal_title_stripped="a\tb"),
            pane("w1:p4", "w1", "w1:t1", "/srv", agent_status=None, terminal_title_stripped=None),
        ]
        result = self.run_cli(["preview", "workspace:w1"], {"tabs": tabs, "panes": panes})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            ANSI_ESCAPE.sub("", result.stdout).splitlines(),
            [
                "editor",
                "  claude  blocked  Fix",
                "  codex   working  a b",
                "  shell   unknown",
                "w1:t2",
                "  shell   unknown  ~/dotfiles",
                "empty",
            ],
        )
        self.assertEqual(self.herdr_calls(), ["tab list --workspace w1", "pane list --workspace w1"])

    def test_malformed_target_is_reported(self) -> None:
        for target in ("w1:p1", "agent:", "workspace:", ""):
            with self.subTest(target=target):
                result = self.run_cli(["preview", target])
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn(f"malformed target {target!r}", result.stderr)
                self.assertEqual(self.herdr_calls(), [])

    def test_herdr_failure_is_reported(self) -> None:
        cases = [
            ("agent:w1:p1", "agent read", "herdr: server not running", "herdr: server not running"),
            (
                "workspace:w9",
                "tab list",
                '{"error":{"code":"workspace_not_found","message":"workspace w9 not found"}}',
                "workspace w9 not found",
            ),
            ("workspace:w1", "pane list", "herdr: server not running", "herdr: server not running"),
        ]
        for target, call, error, detail in cases:
            with self.subTest(call=call):
                result = self.run_cli(["preview", target], env={"HERDR_STUB_FAIL": call, "HERDR_STUB_ERROR": error})
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn(f"{call} ", result.stderr)
                self.assertTrue(result.stderr.rstrip().endswith(f"failed: {detail}"), result.stderr)


# Stands in for fzf: records its arguments, one per NUL-terminated entry, in
# $FAKE_FZF_ARGV and its input rows in $FAKE_FZF_INPUT, then prints input row
# number $FAKE_FZF_CHOICE and exits 0, or, with no choice, exits 130 as fzf does
# on Esc; $FAKE_FZF_STATUS overrides the exit status.
FAKE_FZF = """\
#!/bin/sh
printf '%s\\0' "$@" > "$FAKE_FZF_ARGV"
cat > "$FAKE_FZF_INPUT"
if [ -n "${FAKE_FZF_CHOICE:-}" ]; then
  sed -n "${FAKE_FZF_CHOICE}p" "$FAKE_FZF_INPUT"
  exit "${FAKE_FZF_STATUS:-0}"
fi
exit "${FAKE_FZF_STATUS:-130}"
"""

PICK_FIXTURES: Mapping[str, Records] = {
    "agents": [agent("w1:p1", "blocked", 2), agent("w2:p1", "idle", 1, workspace_id="w2")],
    "workspaces": [workspace("w1", 1), workspace("w2", 2)],
}


@final
class HerdrFindPickTests(HerdrStubTestCase):
    @override
    def setUp(self) -> None:
        super().setUp()
        fake_fzf = self.root / "fzf"
        _ = fake_fzf.write_text(FAKE_FZF)
        fake_fzf.chmod(0o755)
        self.fzf_argv = self.root / "fzf.argv"
        self.fzf_input = self.root / "fzf.input"
        self.env |= {
            "HERDR_FIND_FZF_PATH": str(fake_fzf),
            "FAKE_FZF_ARGV": str(self.fzf_argv),
            "FAKE_FZF_INPUT": str(self.fzf_input),
        }
        for inherited in ("HERDR_PLUGIN_CONTEXT_JSON", "FZF_DEFAULT_OPTS", "FZF_DEFAULT_OPTS_FILE"):
            _ = self.env.pop(inherited, None)

    def run_pick(self, env: Mapping[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        return self.run_cli(["pick"], PICK_FIXTURES, env)

    def fzf_arguments(self) -> list[str]:
        return self.fzf_argv.read_text().split("\0")[:-1]

    def fzf_input_targets(self) -> list[str]:
        """Return the targets of the rows given to fzf, after its header line."""
        header, *listed = self.fzf_input.read_text().splitlines()
        self.assertEqual(header, f"\t{PICKER_KEY_HINTS}")
        return [line.split("\t")[0] for line in listed]

    def binding(self, key: str) -> str:
        """Return the fzf action bound to KEY, failing unless exactly one binding names it."""
        actions = [
            argument.removeprefix(f"--bind={key}:")
            for argument in self.fzf_arguments()
            if argument.startswith(f"--bind={key}:")
        ]
        self.assertEqual(len(actions), 1, self.fzf_arguments())
        return actions[0]

    def run_shell(self, command: str, env: Mapping[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        """Run COMMAND as fzf's --with-shell runs a binding's command."""
        _ = self.log.write_text("")
        fixtures = {f"HERDR_STUB_{key.upper()}": json.dumps(list(records)) for key, records in PICK_FIXTURES.items()}
        return subprocess.run(
            ["/bin/sh", "-c", command],
            env={**self.env, **fixtures, **(env if env is not None else {})},
            text=True,
            capture_output=True,
            check=False,
        )

    def test_enter_focuses_the_chosen_agent(self) -> None:
        # Input line 1 is the header line, which fzf does not let the user choose.
        result = self.run_pick({"FAKE_FZF_CHOICE": "2"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.herdr_calls(), ["agent list", "workspace list", "agent focus w1:p1"])

    def test_enter_focuses_the_chosen_workspace(self) -> None:
        result = self.run_pick({"FAKE_FZF_CHOICE": "5"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.herdr_calls(), ["agent list", "workspace list", "workspace focus w2"])

    def test_closing_without_a_choice_changes_nothing(self) -> None:
        for status in ("1", "130"):
            with self.subTest(status=status):
                result = self.run_pick({"FAKE_FZF_STATUS": status})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")
                self.assertEqual(self.herdr_calls(), ["agent list", "workspace list"])

    def test_focus_failure_is_shown_until_enter(self) -> None:
        error = '{"error":{"code":"pane_not_found","message":"pane w1:p1 not found"}}'
        result = self.run_pick({"FAKE_FZF_CHOICE": "2", "HERDR_STUB_FAIL": "agent focus", "HERDR_STUB_ERROR": error})
        self.assertEqual(result.returncode, 1)
        self.assertIn("agent focus w1:p1 failed: pane w1:p1 not found", result.stderr)
        self.assertTrue(result.stderr.endswith("Press enter to close."), result.stderr)

    def test_listing_failure_is_shown_without_opening_fzf(self) -> None:
        result = self.run_pick({"HERDR_STUB_FAIL": "agent list"})
        self.assertEqual(result.returncode, 1)
        self.assertIn("agent list failed: herdr: server not running", result.stderr)
        self.assertTrue(result.stderr.endswith("Press enter to close."), result.stderr)
        self.assertFalse(self.fzf_argv.exists())

    def test_fzf_failure_is_shown(self) -> None:
        result = self.run_pick({"FAKE_FZF_STATUS": "2"})
        self.assertEqual(result.returncode, 1)
        self.assertIn("fzf exited with status 2", result.stderr)
        self.assertEqual(self.herdr_calls(), ["agent list", "workspace list"])

    def test_caller_comes_from_the_plugin_context(self) -> None:
        context = json.dumps({"workspace_id": "w1", "focused_pane_id": "w1:p1", "tab_id": "w1:t1"})
        result = self.run_pick({"HERDR_PLUGIN_CONTEXT_JSON": context})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.fzf_input_targets(), ["agent:w2:p1", "agent:w1:p1", "workspace:w2", "workspace:w1"])
        self.assertTrue(
            self.binding("ctrl-r").endswith(" reload-action refresh --caller-workspace w1 --caller-pane w1:p1"),
            self.binding("ctrl-r"),
        )

    def test_missing_or_malformed_plugin_context_means_no_caller(self) -> None:
        contexts = [None, "", "not json", "[]", '{"workspace_id": 5, "focused_pane_id": null}']
        for context in contexts:
            with self.subTest(context=context):
                env = {} if context is None else {"HERDR_PLUGIN_CONTEXT_JSON": context}
                result = self.run_pick(env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    self.fzf_input_targets(), ["agent:w1:p1", "agent:w2:p1", "workspace:w1", "workspace:w2"]
                )
                self.assertTrue(self.binding("ctrl-r").endswith(" reload-action refresh"), self.binding("ctrl-r"))

    def test_fzf_searches_the_display_and_keeps_default_movement(self) -> None:
        result = self.run_pick()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = self.fzf_arguments()
        options = ("--delimiter=\t", "--with-nth=2..", "--header-lines=1", "--ansi", "--tiebreak=index")
        for option in (*options, "--with-shell=/bin/sh -c"):
            self.assertIn(option, arguments)
        self.assertEqual(self.binding("ctrl-o"), "toggle-preview")
        self.assertEqual(self.binding("ctrl-u"), "preview-half-page-up")
        self.assertEqual(self.binding("ctrl-d"), "preview-half-page-down")
        for key in ("ctrl-j", "ctrl-k"):
            self.assertFalse(any(key in argument for argument in arguments), arguments)

    def test_preview_command_previews_the_row_target(self) -> None:
        _ = self.run_pick()
        previews = [
            argument.removeprefix("--preview=")
            for argument in self.fzf_arguments()
            if argument.startswith("--preview=")
        ]
        self.assertEqual(len(previews), 1)
        # fzf substitutes {1}, the row's target, as a single-quoted word.
        result = self.run_shell(previews[0].replace("{1}", "'agent:w1:p1'"), {"HERDR_STUB_AGENT_OUTPUT": "out\n"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "out\n")
        self.assertEqual(self.herdr_calls(), ["agent read w1:p1 --source recent-unwrapped --lines 40"])

    def test_filter_keys_toggle_and_refresh_keeps_the_filter(self) -> None:
        _ = self.run_pick()
        cases = [
            # key, current prompt, prompt after the key, rows listed after it
            ("ctrl-a", "> ", "agents> ", ["agent:w1:p1", "agent:w2:p1"]),
            ("ctrl-a", "agents> ", "> ", ["agent:w1:p1", "agent:w2:p1", "workspace:w1", "workspace:w2"]),
            ("ctrl-a", "workspaces> ", "agents> ", ["agent:w1:p1", "agent:w2:p1"]),
            ("ctrl-w", "> ", "workspaces> ", ["workspace:w1", "workspace:w2"]),
            ("ctrl-w", "workspaces> ", "> ", ["agent:w1:p1", "agent:w2:p1", "workspace:w1", "workspace:w2"]),
            ("ctrl-r", "agents> ", None, ["agent:w1:p1", "agent:w2:p1"]),
            ("ctrl-r", "> ", None, ["agent:w1:p1", "agent:w2:p1", "workspace:w1", "workspace:w2"]),
        ]
        for key, prompt, next_prompt, targets in cases:
            with self.subTest(key=key, prompt=prompt):
                transform = self.binding(key)
                self.assertTrue(transform.startswith("transform:"), transform)
                result = self.run_shell(transform.removeprefix("transform:"), {"FZF_PROMPT": prompt})
                self.assertEqual(result.returncode, 0, result.stderr)
                action = result.stdout.rstrip("\n")
                prompt_action, separator, reload_command = action.rpartition("reload:")
                self.assertEqual(separator, "reload:", action)
                expected_prompt_action = "" if next_prompt is None else f"change-prompt({next_prompt})+"
                self.assertEqual(prompt_action, expected_prompt_action)
                listed = self.run_shell(reload_command)
                self.assertEqual(listed.returncode, 0, listed.stderr)
                header, *rows = listed.stdout.splitlines()
                self.assertEqual(header, f"\t{PICKER_KEY_HINTS}")
                self.assertEqual([line.split("\t")[0] for line in rows], targets)

    def reload_command(self, key: str) -> str:
        """Return the rows command KEY's binding reloads with, from the unfiltered picker."""
        transform = self.binding(key).removeprefix("transform:")
        action = self.run_shell(transform, {"FZF_PROMPT": "> "}).stdout.rstrip("\n")
        return action.rpartition("reload:")[2]

    def test_reload_failure_is_shown_in_the_header_line(self) -> None:
        # fzf drops a reload's stderr and keeps the query, which could filter
        # out an error row, but never filters the header line.
        _ = self.run_pick()
        self.assertIn("--header-lines=1", self.fzf_arguments())
        failure = {"HERDR_STUB_FAIL": "agent list", "HERDR_STUB_ERROR": "server\tnot\nrunning"}
        for key in ("ctrl-r", "ctrl-a", "ctrl-w"):
            with self.subTest(key=key):
                listed = self.run_shell(self.reload_command(key), failure)
                self.assertEqual(listed.returncode, 0, listed.stderr)
                lines = listed.stdout.splitlines()
                self.assertEqual(len(lines), 1, lines)
                target, display = lines[0].split("\t")
                self.assertEqual(target, "")
                shown = ANSI_ESCAPE.sub("", display)
                self.assertEqual(shown, "error: herdr agent list failed: server not running")

    def test_real_fzf_never_chooses_the_header_line(self) -> None:
        # --filter prints the rows matching a query without a terminal. The
        # query matches only the header line, so no row matches.
        env = {"HERDR_FIND_FZF_PATH": "", "FZF_DEFAULT_OPTS": "--filter=" + shlex.quote("'ctrl-a agents")}
        result = self.run_pick(env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(self.herdr_calls(), ["agent list", "workspace list"])

    def test_real_fzf_accepts_the_options_and_prints_the_chosen_row(self) -> None:
        # --filter makes fzf print the rows matching a query without a terminal,
        # after parsing every picker option; the picker focuses the first.
        env = {"HERDR_FIND_FZF_PATH": "", "FZF_DEFAULT_OPTS": "--filter=" + shlex.quote("'/srv/w2")}
        result = self.run_pick(env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.herdr_calls(), ["agent list", "workspace list", "workspace focus w2"])


@final
class HerdrFindOpenPopupTests(HerdrStubTestCase):
    def test_opens_the_entrypoint_as_a_focused_plugin_pane(self) -> None:
        result = self.run_cli(["open-popup", "picker"], env={"HERDR_PLUGIN_ID": "dotfiles.find"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.herdr_calls(), ["plugin pane open --plugin dotfiles.find --entrypoint picker --focus"])

    def test_requires_a_plugin_id(self) -> None:
        _ = self.env.pop("HERDR_PLUGIN_ID", None)
        result = self.run_cli(["open-popup", "picker"])
        self.assertEqual(result.returncode, 1)
        self.assertIn("HERDR_PLUGIN_ID is not set", result.stderr)
        self.assertEqual(self.herdr_calls(), [])


if __name__ == "__main__":
    _ = unittest.main()
