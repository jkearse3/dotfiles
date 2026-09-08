import unittest
from dataclasses import replace

from pi_shepherd.ids import marker, tab_label
from pi_shepherd.topology import derive
from support import TeamCase


class TopologyTests(TeamCase):
    def test_healthy_and_only_proof_preserving_automatic_transitions(self) -> None:
        record = self.create()
        self.assertEqual(derive(record, self.runtime.snapshot()).status, "healthy")
        agent = self.runtime.agents[0]
        moved = replace(agent, pane_id="w1:pMoved")
        self.runtime.agents = [moved]
        self.runtime.panes = [
            replace(p, pane_id=moved.pane_id) if p.pane_id == agent.pane_id else p
            for p in self.runtime.panes
        ]
        health = derive(record, self.runtime.snapshot())
        self.assertEqual(health.action, "refresh_pane")
        self.assertTrue(health.automatic)
        updated, health, _ = self.team.observe(record)
        self.assertEqual(updated.pane_id, moved.pane_id)
        assert health.tab is not None
        self.runtime.close_tab(health.tab)
        self.assertEqual(
            derive(updated, self.runtime.snapshot()).action, "finalize_closed"
        )
        updated, health, _ = self.team.observe(updated)
        self.assertEqual(updated.phase, "closed")

    def test_duplicate_markers_aliases_and_contamination(self) -> None:
        record = self.create()
        snapshot = self.runtime.snapshot()
        for changed in (
            replace(
                snapshot,
                tabs=snapshot.tabs + (replace(snapshot.tabs[-1], tab_id="duplicate"),),
            ),
            replace(
                snapshot,
                agents=snapshot.agents
                + (replace(snapshot.agents[0], pane_id="duplicate"),),
            ),
            replace(
                snapshot,
                panes=snapshot.panes + (replace(snapshot.panes[-1], pane_id="extra"),),
            ),
            replace(
                snapshot,
                agents=(),
                panes=tuple(
                    replace(p, kind="foreign") if p.tab_id == record.tab_id else p
                    for p in snapshot.panes
                ),
            ),
            replace(snapshot, agents=(replace(snapshot.agents[0], kind="foreign"),)),
        ):
            with self.subTest(snapshot=changed):
                health = derive(record, changed)
                self.assertIn(
                    health.status, ("ambiguous", "contaminated", "kind_conflict")
                )
                self.assertIsNone(health.action)
                self.assertFalse(health.automatic)

    def test_marker_change_relocation_and_uncertain_launch(self) -> None:
        record = self.create()
        snapshot = self.runtime.snapshot()
        changed = replace(
            snapshot,
            tabs=tuple(
                replace(t, label="changed") if t.tab_id == record.tab_id else t
                for t in snapshot.tabs
            ),
        )
        self.assertEqual(derive(record, changed).action, "restore_marker")
        moved = replace(
            snapshot,
            tabs=tuple(
                replace(t, tab_id="w2:t2", workspace_id="w2")
                if t.tab_id == record.tab_id
                else t
                for t in snapshot.tabs
            ),
            panes=tuple(
                replace(p, tab_id="w2:t2", workspace_id="w2")
                if p.tab_id == record.tab_id
                else p
                for p in snapshot.panes
            ),
            agents=tuple(
                replace(p, tab_id="w2:t2", workspace_id="w2") for p in snapshot.agents
            ),
        )
        self.assertEqual(derive(record, moved).action, "accept_relocation")
        self.assertFalse(derive(record, moved).automatic)
        self.runtime.missing_agent()
        self.assertEqual(
            derive(record, self.runtime.snapshot()).status, "agent_missing"
        )
        self.assertIsNone(derive(record, self.runtime.snapshot()).action)
        uncertain = replace(record, phase="provisioning")
        self.assertEqual(
            derive(uncertain, self.runtime.snapshot()).status, "launch_uncertain"
        )
        self.assertIsNone(derive(uncertain, self.runtime.snapshot()).action)

    def test_task_label_requires_exact_name_and_unique_identity(self) -> None:
        record = self.registry.reserve(
            self.team.context.endpoint, "w1", "task-review", "pi", "pi", str(self.root)
        )
        tab, _ = self.runtime.create_tab(
            "w1", str(self.root), tab_label(record.teammate_id, record.logical_name), ()
        )
        self.assertEqual(derive(record, self.runtime.snapshot()).action, "bind")
        for label in (
            tab_label(record.teammate_id, "wrong-task"),
            tab.label + " extra",
            "prefix " + tab.label,
        ):
            with self.subTest(label=label):
                self.runtime.tabs[-1] = replace(tab, label=label)
                health = derive(record, self.runtime.snapshot())
                self.assertEqual(health.status, "marker_conflict")
                self.assertIsNone(health.action)
        self.runtime.tabs[-1] = tab
        _ = self.runtime.create_tab(
            "w1", str(self.root), marker(record.teammate_id), ()
        )
        health = derive(record, self.runtime.snapshot())
        self.assertEqual(health.status, "ambiguous")
        self.assertIsNone(health.action)

    def test_provisioning_requires_exact_task_label(self) -> None:
        record = self.registry.reserve(
            self.team.context.endpoint, "w1", "worker", None, "pi", str(self.root)
        )
        tab, _ = self.runtime.create_tab(
            "w1",
            str(self.root),
            tab_label(record.teammate_id, record.logical_name),
            (),
        )
        health = derive(record, self.runtime.snapshot())
        self.assertEqual(health.action, "bind")
        self.assertTrue(health.automatic)
        for label in (
            marker(record.teammate_id),
            "prefix " + marker(record.teammate_id),
        ):
            with self.subTest(label=label):
                self.runtime.tabs[-1] = replace(tab, label=label)
                self.assertEqual(
                    derive(record, self.runtime.snapshot()).status,
                    "marker_conflict",
                )


if __name__ == "__main__":
    _ = unittest.main()
