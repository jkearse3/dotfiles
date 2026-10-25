from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import final, override

CLI = os.environ["HERDR_FIND"]

# Records each call, one per line, and answers agent, workspace, and pane list
# with $HERDR_STUB_AGENTS, $HERDR_STUB_WORKSPACES, and $HERDR_STUB_PANES, each
# a JSON list placed under the reply's result. The call named by
# $HERDR_STUB_FAIL, such as "agent list", fails as Herdr does.
HERDR_STUB = """\
#!/bin/sh
printf '%s\\n' "$*" >> "$HERDR_STUB_LOG"
if [ "$1 $2" = "${HERDR_STUB_FAIL:-}" ]; then
  echo "herdr: server not running" >&2
  exit 1
fi
case "$1 $2" in
  "agent list")
    printf '{"result":{"type":"agent_list","agents":%s}}\\n' "$HERDR_STUB_AGENTS" ;;
  "workspace list")
    printf '{"result":{"type":"workspace_list","workspaces":%s}}\\n' "$HERDR_STUB_WORKSPACES" ;;
  "pane list")
    printf '{"result":{"type":"pane_list","panes":%s}}\\n' "$HERDR_STUB_PANES" ;;
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


def pane(pane_id: str, workspace_id: str, tab_id: str, cwd: str, *, focused: bool = False) -> dict[str, object]:
    """Return a pane record shaped like one from ``herdr pane list``."""
    return {
        "agent_status": "unknown",
        "cwd": cwd,
        "focused": focused,
        "pane_id": pane_id,
        "tab_id": tab_id,
        "terminal_title_stripped": "~",
        "workspace_id": workspace_id,
    }


@final
class HerdrFindRowsTests(unittest.TestCase):
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
            "HERDR_STUB_PANES": "[]",
        }

    def run_rows(
        self,
        arguments: Sequence[str] = (),
        fixtures: Mapping[str, Records] | None = None,
        env: Mapping[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        """Run ``rows`` with the stub answering from FIXTURES: agents, workspaces, or panes."""
        _ = self.log.write_text("")
        run_env = dict(self.env)
        if fixtures is not None:
            for key, records in fixtures.items():
                run_env[f"HERDR_STUB_{key.upper()}"] = json.dumps(list(records))
        if env is not None:
            run_env.update(env)
        return subprocess.run(
            [CLI, "rows", *arguments],
            env=run_env,
            text=True,
            capture_output=True,
            check=False,
        )

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

    def herdr_calls(self) -> list[str]:
        return self.log.read_text().splitlines()

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
        for call in ("agent list", "workspace list", "pane list"):
            with self.subTest(call=call):
                result = self.run_rows(
                    fixtures={"workspaces": [workspace("w1", 1, worktree=None)]}, env={"HERDR_STUB_FAIL": call}
                )
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn(f"{call} failed: herdr: server not running", result.stderr)

    def test_malformed_herdr_reply_exits_non_zero_with_error(self) -> None:
        result = self.run_rows(env={"HERDR_STUB_AGENTS": "not json"})
        self.assertEqual(result.returncode, 1)
        self.assertIn("returned malformed JSON", result.stderr)


if __name__ == "__main__":
    _ = unittest.main()
