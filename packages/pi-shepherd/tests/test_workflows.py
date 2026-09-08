"""Every lifecycle effect boundary uses fake Herdr and disposable intent."""

import unittest
from collections.abc import Sequence
from dataclasses import replace
from typing import cast
from unittest.mock import patch

from pi_shepherd.errors import TeamError
from pi_shepherd.ids import marker, tab_label
from pi_shepherd.messages import request
from pi_shepherd.models import Pane, Tab
from support import TeamCase


class LifecycleTests(TeamCase):
    def test_create_close_and_result_retention(self) -> None:
        record = self.create()
        self.assertEqual(
            self.runtime.tabs[-1].label,
            f"worker [pi-shepherd:{record.teammate_id}]",
        )
        request = self.registry.prepare(record)
        pending = self.team.show(record.teammate_id)["request"]
        assert isinstance(pending, dict)
        self.assertEqual(pending["request_status"], "pending")
        self.registry.reply(request.request_id, record.teammate_id, "retained")
        completed = self.team.show(record.teammate_id)["request"]
        assert isinstance(completed, dict)
        self.assertEqual(completed["request_status"], "completed")
        _ = self.team.close(record.teammate_id, False)
        self.assertEqual(self.runtime.calls, ["create", "start", "close"])
        self.assertEqual(self.registry.request(request.request_id).reply, "retained")
        self.assertEqual(self.team.show(record.teammate_id)["health"], "closed")

    def test_twin_and_profile_launches_remain_distinct(self) -> None:
        with (
            patch.object(
                self.runtime, "create_tab", wraps=self.runtime.create_tab
            ) as create_tab,
            patch.object(self.runtime, "start", wraps=self.runtime.start) as start,
        ):
            twin = self.create("twin")
            self.assertIsNone(twin.profile)
            self.assertEqual(
                start.call_args.args[3],
                (
                    "--provider",
                    "test-provider",
                    "--model",
                    "test-model",
                    "--thinking",
                    "medium",
                ),
            )
            twin_environment = cast(
                tuple[tuple[str, str], ...], create_tab.call_args.args[3]
            )
            self.assertIn(
                ("PI_SHEPHERD_TEAMMATE_ID", twin.teammate_id), twin_environment
            )
            self.assertNotIn(("MODE", "configured"), twin_environment)

            configured = self.create_profile("configured")
            self.assertEqual(configured.profile, "configured")
            self.assertEqual(start.call_args.args[3], ("--model", "configured-model"))
            profile_environment = cast(
                tuple[tuple[str, str], ...], create_tab.call_args.args[3]
            )
            self.assertIn(("MODE", "configured"), profile_environment)
            self.assertIn(
                ("PI_SHEPHERD_TEAMMATE_ID", configured.teammate_id),
                profile_environment,
            )

    def test_invalid_twin_context_fails_before_mutation(self) -> None:
        del self.runtime.environment["PI_PROVIDER"]

        with self.assertRaises(TeamError) as caught:
            _ = self.team.create("invalid", None, None, 4)

        self.assertEqual(caught.exception.code, "caller_context")
        self.assertEqual(
            caught.exception.message,
            "Calling Pi configuration is missing PI_PROVIDER",
        )
        self.assertEqual(self.runtime.calls, [])
        self.assertEqual(
            self.registry.list(self.team.context.endpoint, "w1", True),
            [],
        )

    def test_creation_excludes_observation_until_binding_and_startup(self) -> None:
        original = self.runtime.create_tab

        def inspect_during_create(
            workspace: str,
            cwd: str,
            label: str,
            environment: Sequence[tuple[str, str]],
        ) -> tuple[Tab, Pane]:
            tab, pane = original(workspace, cwd, label, environment)
            record = self.registry.list(self.team.context.endpoint, workspace, False)[0]
            # Separate lock acquisition models an observer after Herdr created the tab
            # but before create received and committed the response.
            with self.assertRaises(TeamError) as caught:
                _ = self.team.show(record.teammate_id)
            self.assertEqual(caught.exception.code, "busy")
            self.assertEqual(self.registry.get(record.teammate_id), record)
            return tab, pane

        with patch.object(self.runtime, "create_tab", new=inspect_during_create):
            record = self.create()
        self.assertEqual(self.runtime.calls, ["create", "start"])
        self.assertEqual(self.team.show(record.teammate_id)["health"], "healthy")

    def test_uncertain_create_is_not_replayed(self) -> None:
        self.runtime.failure = "create"
        with self.assertRaises(TeamError):
            _ = self.create()
        record = self.registry.list(self.team.context.endpoint, "w1", True)[0]
        self.assertEqual(record.phase, "provisioning")
        self.assertIsNone(record.tab_id)
        _ = self.team.repair(record.teammate_id, True)
        self.assertEqual(self.runtime.calls, ["create"])

    def test_uncertain_start_stays_provisioning_and_never_restarts(self) -> None:
        self.runtime.failure = "start"
        with self.assertRaises(TeamError):
            _ = self.create()
        record = self.registry.list(self.team.context.endpoint, "w1", True)[0]
        self.assertIsNotNone(record.tab_id)
        self.assertEqual(
            self.team.repair(record.teammate_id, True)["health"], "launch_uncertain"
        )
        self.assertEqual(self.runtime.calls.count("start"), 1)

    def test_creation_rejects_reused_topology_and_wrong_cwd_before_start(self) -> None:
        original = self.runtime.create_tab
        for mode in ("reused", "cwd", "focused"):

            def bad_create(
                workspace: str,
                cwd: str,
                label: str,
                environment: Sequence[tuple[str, str]],
                *,
                failure_mode: str = mode,
            ) -> tuple[Tab, Pane]:
                tab, pane = original(workspace, cwd, label, environment)
                if failure_mode == "reused":
                    return tab, replace(pane, terminal_id="term1")
                if failure_mode == "cwd":
                    return tab, replace(pane, cwd="/nonexistent")
                return replace(tab, focused=True), pane

            with (
                self.subTest(mode=mode),
                patch.object(self.runtime, "create_tab", new=bad_create),
                self.assertRaises(TeamError),
            ):
                _ = self.create(mode)
        self.assertNotIn("start", self.runtime.calls)

    def test_uncertain_close_keeps_intent_and_requires_explicit_resume(self) -> None:
        record = self.create()
        self.runtime.failure = "close"
        with self.assertRaises(TeamError):
            _ = self.team.close(record.teammate_id, False)
        self.assertEqual(self.registry.get(record.teammate_id).phase, "closing")
        self.assertEqual(
            self.team.show(record.teammate_id)["repair_action"], "resume_close"
        )
        self.assertEqual(self.runtime.calls.count("close"), 1)
        self.runtime.failure = None
        _ = self.team.repair(record.teammate_id, True)
        self.assertEqual(self.runtime.calls.count("close"), 2)
        self.assertEqual(self.registry.get(record.teammate_id).phase, "closed")

    def test_interrupted_close_rejects_replacement_shell_pane(self) -> None:
        record = self.create()
        self.runtime.failure = "close"
        with self.assertRaises(TeamError):
            _ = self.team.close(record.teammate_id, False)
        self.runtime.failure = None
        self.runtime.missing_agent()
        self.runtime.panes = [
            replace(p, pane_id="replacement", terminal_id="replacement-terminal")
            if p.tab_id == record.tab_id
            else p
            for p in self.runtime.panes
        ]
        repair = self.team.repair(record.teammate_id, True)
        self.assertEqual(repair["health"], "binding_conflict")
        self.assertFalse(repair["applied"])
        for force in (False, True):
            with self.assertRaises(TeamError):
                _ = self.team.close(record.teammate_id, force)
        self.assertEqual(self.runtime.calls.count("close"), 1)
        self.assertEqual(self.registry.get(record.teammate_id).phase, "closing")

    def test_force_never_bypasses_final_tab_or_contamination(self) -> None:
        record = self.create()
        snapshot = self.runtime.snapshot()
        self.runtime.tabs = [
            tab for tab in self.runtime.tabs if tab.tab_id == record.tab_id
        ]
        self.runtime.panes = [
            pane for pane in self.runtime.panes if pane.tab_id == record.tab_id
        ]
        assert record.pane_id is not None
        self.runtime.caller_id = record.pane_id
        with self.assertRaises(TeamError) as caught:
            _ = self.team.close(record.teammate_id, True)
        self.assertEqual(caught.exception.code, "final_tab")
        self.runtime.tabs = list(snapshot.tabs)
        self.runtime.panes = list(snapshot.panes) + [
            replace(snapshot.panes[-1], pane_id="extra")
        ]
        self.runtime.caller_id = "w1:p1"
        with self.assertRaises(TeamError):
            _ = self.team.close(record.teammate_id, True)
        self.assertNotIn("close", self.runtime.calls)

    def test_missing_agent_repair_only_guides_and_preserves_inbox(self) -> None:
        record = self.create()
        request = self.registry.prepare(record)
        self.runtime.missing_agent()
        for apply in (False, True):
            result = self.team.repair(record.teammate_id, apply)
            self.assertEqual(result["health"], "agent_missing")
            self.assertIsNone(result["action"])
            self.assertFalse(result["applied"])
            self.assertIn("explicitly close", str(result["guidance"]))
            self.assertEqual(self.registry.request(request.request_id), request)
        self.assertEqual(self.runtime.calls, ["create", "start"])
        with self.assertRaises(TeamError):
            _ = self.team.close(record.teammate_id, False)
        self.registry.cancel(request.request_id)
        self.runtime.is_shell_ready = False
        for force in (False, True):
            with self.assertRaises(TeamError):
                _ = self.team.close(record.teammate_id, force)
        self.assertNotIn("close", self.runtime.calls)

    def test_close_create_uses_updated_profile_and_keeps_old_results(self) -> None:
        record = self.create_profile()
        request = self.registry.prepare(record)
        self.registry.reply(request.request_id, record.teammate_id, "retained")
        self.runtime.missing_agent()
        _ = self.team.close(record.teammate_id, False)
        profile = self.config.profiles["configured"]
        updated_profile = replace(
            profile, args=("new-argument",), env=(("MODE", "new"),)
        )
        self.team.config = replace(
            self.config, profiles={"configured": updated_profile}
        )
        with (
            patch.object(
                self.runtime, "create_tab", wraps=self.runtime.create_tab
            ) as create_tab,
            patch.object(self.runtime, "start", wraps=self.runtime.start) as start,
        ):
            replacement = self.create_profile()
            self.assertIn(
                ("MODE", "new"),
                cast(tuple[tuple[str, str], ...], create_tab.call_args.args[3]),
            )
            self.assertEqual(start.call_args.args[3], ("new-argument",))
        self.assertNotEqual(replacement.teammate_id, record.teammate_id)
        self.assertNotEqual(replacement.tab_id, record.tab_id)
        self.assertEqual(replacement.logical_name, record.logical_name)
        self.assertEqual(self.registry.request(request.request_id).reply, "retained")

    def test_relocation_requires_full_id_and_changes_name_scope(self) -> None:
        record = self.create()
        self.runtime.tabs = [
            replace(t, workspace_id="w2", tab_id="w2:t2")
            if t.tab_id == record.tab_id
            else t
            for t in self.runtime.tabs
        ]
        self.runtime.panes = [
            replace(p, workspace_id="w2", tab_id="w2:t2", pane_id="w2:p2")
            if p.tab_id == record.tab_id
            else p
            for p in self.runtime.panes
        ]
        self.runtime.agents = [
            replace(p, workspace_id="w2", tab_id="w2:t2", pane_id="w2:p2")
            for p in self.runtime.agents
        ]
        with self.assertRaises(TeamError):
            _ = self.team.repair("worker", True)
        with self.assertRaises(TeamError):
            _ = request(self.team, record.teammate_id, "text", False, 0, True)
        _ = self.team.repair(record.teammate_id, True)
        self.assertEqual(self.registry.get(record.teammate_id).workspace_id, "w2")
        with self.assertRaises(TeamError):
            _ = self.team.show("worker")
        self.assertEqual(self.team.show(record.teammate_id)["health"], "healthy")

    def test_restore_marker_only_on_exact_bound_tab(self) -> None:
        record = self.create()
        self.runtime.tabs[-1] = replace(self.runtime.tabs[-1], label="changed")
        self.assertEqual(
            self.team.repair(record.teammate_id, False)["action"], "restore_marker"
        )
        self.assertNotIn("rename", self.runtime.calls)
        _ = self.team.repair(record.teammate_id, True)
        self.assertEqual(
            self.runtime.tabs[-1].label,
            tab_label(record.teammate_id, record.logical_name),
        )

    def test_marker_repair_rejects_another_teammates_identity(self) -> None:
        first = self.create("first")
        second = self.create("second")
        for foreign_label in (
            marker(second.teammate_id),
            tab_label(second.teammate_id, second.logical_name),
        ):
            with self.subTest(label=foreign_label):
                self.runtime.tabs = [
                    replace(tab, label=foreign_label)
                    if tab.tab_id == first.tab_id
                    else tab
                    for tab in self.runtime.tabs
                ]
                self.assertEqual(
                    self.team.show(second.teammate_id)["health"], "ambiguous"
                )
                repair = self.team.repair(first.teammate_id, True)
                self.assertEqual(repair["health"], "marker_conflict")
                self.assertFalse(repair["applied"])
                self.assertNotIn("rename", self.runtime.calls)

    def test_marker_without_task_name_is_rejected(self) -> None:
        record = self.create()
        self.runtime.tabs[-1] = replace(
            self.runtime.tabs[-1], label=marker(record.teammate_id)
        )
        repair = self.team.repair(record.teammate_id, True)
        self.assertEqual(repair["health"], "marker_conflict")
        self.assertFalse(repair["applied"])
        self.assertEqual(self.registry.get(record.teammate_id), record)
        with self.assertRaises(TeamError):
            _ = request(self.team, record.teammate_id, "text", False, 0, True)
        self.assertEqual(self.runtime.calls, ["create", "start"])

    def test_forget_requires_closed_empty_or_prominent_force_warning(self) -> None:
        record = self.create()
        with self.assertRaises(TeamError):
            _ = self.team.forget(record.teammate_id, False)
        result = self.team.forget(record.teammate_id, True)
        warning = result["warning"]
        assert isinstance(warning, str)
        self.assertIn("WARNING", warning)
        self.assertNotIn("close", self.runtime.calls)


if __name__ == "__main__":
    _ = unittest.main()
