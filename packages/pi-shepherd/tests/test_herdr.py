"""Protocol-22 wire shapes and invocation failures, independent of the domain fake."""

# unittest mock interfaces are dynamically typed; wire data stays object-typed.
# pyright: reportAny=false, reportUnusedCallResult=false, reportImplicitOverride=false

import copy
import json
import subprocess
import unittest
from unittest.mock import patch

from pi_shepherd.context import discover
from pi_shepherd.errors import TeamError
from pi_shepherd.herdr import HERDR_PROTOCOL, Herdr, decode_pane, decode_snapshot


def pane_wire() -> dict[str, object]:
    return {
        "pane_id": "w1:p1",
        "terminal_id": "terminal1",
        "workspace_id": "w1",
        "tab_id": "w1:t1",
        "focused": True,
        "agent_status": "idle",
        "revision": 1,
        "agent": "pi",
        "name": "test-agent",
        "cwd": "/disposable",
    }


def snapshot_wire() -> dict[str, object]:
    return {
        "version": "0.9.0",
        "protocol": HERDR_PROTOCOL,
        "focused_workspace_id": "w1",
        "focused_tab_id": "w1:t1",
        "focused_pane_id": "w1:p1",
        "workspaces": [
            {
                "workspace_id": "w1",
                "number": 1,
                "label": "test",
                "focused": True,
                "active_tab_id": "w1:t1",
                "tab_count": 1,
                "pane_count": 1,
                "agent_status": "idle",
            }
        ],
        "tabs": [
            {
                "tab_id": "w1:t1",
                "workspace_id": "w1",
                "number": 1,
                "label": "test",
                "pane_count": 1,
                "focused": True,
                "agent_status": "idle",
            }
        ],
        "panes": [pane_wire()],
        "agents": [pane_wire()],
        "layouts": [],
    }


class HerdrTests(unittest.TestCase):
    def test_complete_snapshot_and_additive_native_data(self) -> None:
        raw = snapshot_wire()
        raw["future"] = {"anything": True}
        raw["agents"] = [{**pane_wire(), "agent_session": {"value": "must not retain"}}]
        snapshot = decode_snapshot(raw)
        self.assertEqual(snapshot.agents[0].name, "test-agent")
        self.assertNotIn("must not retain", repr(snapshot))
        for field in ("workspaces", "tabs", "panes", "agents", "layouts", "protocol"):
            changed = copy.deepcopy(raw)
            del changed[field]
            with self.subTest(field=field), self.assertRaises(TeamError):
                decode_snapshot(changed)

    def test_duplicate_and_malformed_topology_fails_closed(self) -> None:
        for patch_value in (
            {"panes": [pane_wire(), pane_wire()]},
            {"agents": [pane_wire(), pane_wire()]},
            {"agents": [{**pane_wire(), "terminal_id": "wrong"}]},
            {"panes": [{**pane_wire(), "tab_id": "missing"}]},
            {"panes": [{**pane_wire(), "focused": False}]},
            {"focused_workspace_id": None},
            {"protocol": True},
            {"protocol": HERDR_PROTOCOL - 1},
            {"panes": [{**pane_wire(), "agent_status": "new_unknown_status"}]},
            {"panes": [{**pane_wire(), "revision": -1}]},
        ):
            with self.subTest(value=patch_value), self.assertRaises(TeamError):
                decode_snapshot({**snapshot_wire(), **patch_value})

    def test_wrong_mutation_binding_is_uncertain_and_diagnostics_redacted(self) -> None:
        runtime = Herdr(environment={})
        pane = decode_pane(pane_wire())
        payload = {
            "id": "test",
            "result": {
                "type": "agent_prompted",
                "agent": {**pane_wire(), "pane_id": "wrong"},
            },
        }
        completed = subprocess.CompletedProcess(
            [], 0, json.dumps(payload).encode(), b""
        )
        with patch("pi_shepherd.herdr.subprocess.run", return_value=completed) as run:
            with self.assertRaises(TeamError) as caught:
                runtime.prompt(pane, "sensitive prompt")
            self.assertTrue(caught.exception.uncertain)
            self.assertEqual(run.call_count, 1)
            self.assertNotIn("sensitive prompt", str(caught.exception))
        for code, uncertain in ((1, True), (2, False), (-9, True)):
            completed = subprocess.CompletedProcess([], code, b"", b"sensitive prompt")
            with patch("pi_shepherd.herdr.subprocess.run", return_value=completed):
                with self.assertRaises(TeamError) as caught:
                    runtime.prompt(pane, "sensitive prompt")
                self.assertEqual(caught.exception.uncertain, uncertain)
                self.assertNotIn("sensitive prompt", str(caught.exception))

    def test_timeout_and_malformed_success_are_never_replayed(self) -> None:
        runtime = Herdr(environment={})
        for outcome in (b"not JSON", b"\xff"):
            with patch(
                "pi_shepherd.herdr.subprocess.run",
                return_value=subprocess.CompletedProcess([], 0, outcome, b""),
            ) as run:
                with self.assertRaises(TeamError) as caught:
                    runtime.prompt(decode_pane(pane_wire()), "text")
                self.assertTrue(caught.exception.uncertain)
                self.assertEqual(run.call_count, 1)
        with patch(
            "pi_shepherd.herdr.subprocess.run",
            side_effect=subprocess.TimeoutExpired("redacted", 1),
        ):
            with self.assertRaises(TeamError) as caught:
                runtime.prompt(decode_pane(pane_wire()), "text")
            self.assertTrue(caught.exception.uncertain)

    def test_current_uses_terminal_identity_not_inherited_workspace(self) -> None:
        runtime = Herdr(
            environment={
                "HERDR_ENV": "1",
                "HERDR_SOCKET_PATH": "/disposable/socket",
                "HERDR_WORKSPACE_ID": "stale",
            }
        )
        with (
            patch.object(runtime, "compatibility"),
            patch.object(
                runtime,
                "current",
                return_value=decode_pane({**pane_wire(), "pane_id": "old"}),
            ),
            patch.object(
                runtime, "snapshot", return_value=decode_snapshot(snapshot_wire())
            ),
        ):
            self.assertEqual(discover(runtime).caller.pane_id, "w1:p1")
        with (
            patch.object(runtime, "compatibility"),
            patch.object(
                runtime,
                "current",
                return_value=decode_pane({**pane_wire(), "terminal_id": "absent"}),
            ),
            patch.object(
                runtime, "snapshot", return_value=decode_snapshot(snapshot_wire())
            ),
            self.assertRaises(TeamError),
        ):
            discover(runtime)

    def test_shell_ready_requires_positive_process_evidence(self) -> None:
        runtime = Herdr(environment={})
        cases: tuple[tuple[dict[str, object], bool], ...] = (
            (
                {
                    "shell_pid": 1,
                    "foreground_process_group_id": 1,
                    "foreground_processes": [{"pid": 1}],
                },
                True,
            ),
            (
                {
                    "shell_pid": 1,
                    "foreground_process_group_id": 2,
                    "foreground_processes": [{"pid": 2}],
                },
                False,
            ),
            (
                {
                    "shell_pid": 1,
                    "foreground_process_group_id": 1,
                    "foreground_processes": [],
                },
                False,
            ),
        )
        for process, expected in cases:
            with patch.object(
                runtime,
                "call",
                return_value={"process_info": {"pane_id": "w1:p1", **process}},
            ) as call:
                self.assertEqual(
                    runtime.shell_ready(decode_pane(pane_wire())), expected
                )
                self.assertEqual(
                    call.call_args.args[0], ("pane", "process-info", "--pane", "w1:p1")
                )


if __name__ == "__main__":
    unittest.main()
