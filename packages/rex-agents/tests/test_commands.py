"""Tests for start, resume, release, ls, and the shared command line."""

from __future__ import annotations

import json
import threading
import unittest
from typing import override

from tests.fakes import PARENT, PARENT_WINDOW, START_TIME, Harness


class CommandTestCase(unittest.TestCase):
    @override
    def setUp(self) -> None:
        self.h = Harness()
        self.addCleanup(self.h.cleanup)


class CommandLineTest(CommandTestCase):
    def test_missing_parent_exits_2_naming_rex_block(self) -> None:
        for parent in ("", "block:", "abc", "block:XYZ"):
            status, _, err = self.h.run("ls", parent=parent)
            self.assertEqual(status, 2)
            self.assertIn("REX_BLOCK", err)

    def test_help_exits_0(self) -> None:
        argvs: list[list[str]] = [[], ["start"], ["watch"], ["resume"], ["release"], ["ls"]]
        for argv in argvs:
            status, _, _ = self.h.run(*argv, "--help")
            self.assertEqual(status, 0, argv)


class StartTest(CommandTestCase):
    def test_start_opens_registers_and_prints(self) -> None:
        helper = self.h.start("probe")
        stem = f"probe-{int(START_TIME)}"
        result = self.h.root / "tmp" / "agent-reports" / f"{stem}-{int(START_TIME)}.md"
        self.assertEqual(
            helper,
            {
                "name": stem,
                "harness": "claude",
                "block": helper["block"],
                "dir": str(self.h.root / "work"),
                "result": str(result),
            },
        )
        self.assertTrue(result.parent.is_dir())
        opened = self.h.rex.opened[0]
        self.assertEqual(opened["label"], stem)
        self.assertEqual(opened["cwd"], str(self.h.root / "work"))
        command = opened["command"]
        self.assertEqual(command[:3], ["claude", "--name", stem])
        task = command[3]
        self.assertTrue(task.startswith("Do it.\n\n"))
        self.assertIn(f"to {result}, then end your turn", task)
        self.assertIn("Start no agents unless the user authorizes it", task)
        self.assertIn("Another agent started you", task)
        status, out, _ = self.h.run("ls", "--json")
        self.assertEqual(json.loads(out)[0]["block"], helper["block"])

    def test_harness_commands(self) -> None:
        pi = self.h.start("a", "pi")
        self.h.clock.time += 1
        opencode = self.h.start("b", "opencode")
        pi_command = self.h.rex.opened[0]["command"]
        opencode_command = self.h.rex.opened[1]["command"]
        self.assertEqual(pi_command[:5], ["pi", "--session-id", pi["name"], "--name", pi["name"]])
        self.assertEqual(
            opencode_command[:4], ["opencode", "--session", f"ses_{opencode['name']}", "--prompt"]
        )

    def test_task_from_stdin(self) -> None:
        status, _, err = self.h.run(
            "start", "probe", "--harness", "pi", "--task", "-", "-C", str(self.h.root / "work"),
            stdin="From stdin.",
        )  # fmt: skip
        self.assertEqual(status, 0, err)
        self.assertTrue(self.h.rex.opened[0]["command"][-1].startswith("From stdin."))

    def test_bad_names_and_harness_exit_2(self) -> None:
        for name in ("Bad_Name", "", "a" * 22, "a b"):
            status, _, _ = self.h.run("start", name, "--harness", "claude", "--task", "x")
            self.assertEqual(status, 2, name)
        status, _, _ = self.h.run("start", "ok", "--harness", "codex", "--task", "x")
        self.assertEqual(status, 2)
        self.assertEqual(self.h.rex.opened, [])

    def test_taken_stem_exits_1(self) -> None:
        _ = self.h.start("probe")
        status, _, err = self.h.run("start", "probe", "--harness", "claude", "--task", "x")
        self.assertEqual(status, 1)
        self.assertIn("another name", err)
        self.assertEqual(len(self.h.rex.opened), 1)

    def test_concurrent_starts_from_two_parents_reserve_once(self) -> None:
        other = "block:00000000-0000-0000-0000-0000000000ee"
        self.h.rex.blocks[other] = self.h.rex.blocks[PARENT]
        statuses: list[int] = []
        barrier = threading.Barrier(2)

        def start(parent: str) -> None:
            _ = barrier.wait()
            status, _, _ = self.h.run(
                "start", "probe", "--harness", "claude", "--task", "x",
                "-C", str(self.h.root / "work"), parent=parent,
            )  # fmt: skip
            statuses.append(status)

        threads = [threading.Thread(target=start, args=(p,)) for p in (PARENT, other)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(sorted(statuses), [0, 1])
        self.assertEqual(len(self.h.rex.opened), 1)

    def test_open_failure_registers_nothing(self) -> None:
        self.h.rex.failing.add("open_tab")
        status, _, err = self.h.run("start", "probe", "--harness", "claude", "--task", "x")
        self.assertEqual(status, 1)
        self.assertIn("open_tab failed", err)
        self.assertEqual(json.loads(self.h.run("ls", "--json")[1]), [])

    def test_register_failure_closes_the_block(self) -> None:
        parent_dir = self.h.root / "state" / "rex-agents" / "parents" / PARENT
        parent_dir.mkdir(parents=True)
        (parent_dir / "registry.jsonl").mkdir()  # Appending to a directory fails.
        status, _, _ = self.h.run("start", "probe", "--harness", "claude", "--task", "x")
        self.assertEqual(status, 1)
        self.assertEqual(self.h.rex.closed, [self.h.rex.opened[0]["block"]])

    def test_new_tab_goes_after_the_last_open_helper(self) -> None:
        first = self.h.start("one")
        _ = self.h.rex.add_tab("user tab")
        self.h.clock.time += 1
        second = self.h.start("two")
        order = [t.label for t in self.h.rex.tabs_in_order]
        self.assertEqual(order, ["parent", first["name"], second["name"], "user tab"])
        # Released helpers no longer anchor placement.
        _ = self.h.run("release", second["name"])
        _ = self.h.run("release", first["name"])
        self.h.clock.time += 1
        third = self.h.start("three")
        order = [t.label for t in self.h.rex.tabs_in_order]
        self.assertEqual(order, ["parent", third["name"], "user tab"])

    def test_failed_move_keeps_start_successful(self) -> None:
        _ = self.h.rex.add_tab("user tab")
        self.h.rex.failing.add("move_tab_after")
        helper = self.h.start("probe")
        order = [t.window for t in self.h.rex.tabs_in_order]
        self.assertEqual(order[-1], self.h.rex.blocks[helper["block"]].window)


class ResumeReleaseTest(CommandTestCase):
    def test_resume_continues_the_session_in_a_new_tab(self) -> None:
        first = self.h.start("probe")
        self.h.rex.set_status(first["block"], "done", "2026-01-01T00:00:00Z")
        self.h.clock.time += 30
        status, out, err = self.h.run("resume", "probe", "--task", "Again.")
        self.assertEqual(status, 0, err)
        second = json.loads(out)
        self.assertEqual(second["name"], first["name"])
        self.assertNotEqual(second["block"], first["block"])
        self.assertNotEqual(second["result"], first["result"])
        self.assertEqual(self.h.rex.closed, [first["block"]])
        opened = self.h.rex.opened[1]
        self.assertEqual(opened["command"][:3], ["claude", "--resume", first["name"]])
        task = opened["command"][3]
        self.assertTrue(task.startswith("Again.\n\n"))
        self.assertIn(f"Do not write to the earlier result file, {first['result']}", task)
        self.assertIn(f"write `no earlier context` to {second['result']}", task)
        states = [(r["block"], r["state"]) for r in json.loads(self.h.run("ls", "--json")[1])]
        self.assertEqual(states, [(first["block"], "released"), (second["block"], "starting")])

    def test_resume_forms(self) -> None:
        for harness, expected in (("pi", ["pi", "--session-id"]), ("opencode", ["opencode", "--session"])):
            helper = self.h.start(harness, harness)
            self.h.rex.set_status(helper["block"], "idle", "2026-01-01T00:00:00Z")
            self.h.clock.time += 1
            status, _, err = self.h.run("resume", helper["name"], "--task", "Again.")
            self.assertEqual(status, 0, err)
            self.assertEqual(self.h.rex.opened[-1]["command"][:2], expected)
            self.assertEqual(self.h.rex.opened[-1]["cwd"], helper["dir"])

    def test_resume_refuses_busy_helpers(self) -> None:
        helper = self.h.start("probe")
        cases: list[tuple[str, list[dict[str, object]]]] = [
            ("starting", []),
            ("working", [{"state": "working", "updated_at": "t"}]),
            ("blocked", [{"state": "blocked", "updated_at": "t", "kind": "permission"}]),
        ]
        for state, records in cases:
            self.h.rex.blocks[helper["block"]].records = records
            status, _, err = self.h.run("resume", "probe", "--task", "x")
            self.assertEqual(status, 1, state)
            self.assertIn(f"is {state}", err)
        self.assertEqual(self.h.rex.closed, [])

    def test_resume_released_helper_by_full_stem(self) -> None:
        helper = self.h.start("probe")
        _ = self.h.run("release", "probe")
        status, _, _ = self.h.run("resume", "probe", "--task", "x")
        self.assertEqual(status, 1)  # The short name matches unreleased helpers only.
        self.h.clock.time += 1
        status, out, err = self.h.run("resume", helper["name"], "--task", "x")
        self.assertEqual(status, 0, err)
        self.assertEqual(json.loads(out)["name"], helper["name"])

    def test_unknown_or_ambiguous_names_list_stems(self) -> None:
        one = self.h.start("probe")
        status, _, err = self.h.run("resume", "nope", "--task", "x")
        self.assertEqual(status, 1)
        self.assertIn(one["name"], err)
        status, _, err = self.h.run("release", "nope")
        self.assertEqual(status, 1)
        self.assertIn(one["name"], err)

    def test_release_is_idempotent_and_closes_only_the_block(self) -> None:
        helper = self.h.start("probe")
        split = "block:split"
        self.h.rex.blocks[split] = type(self.h.rex.blocks[helper["block"]])(
            self.h.rex.blocks[helper["block"]].window
        )
        self.assertEqual(self.h.run("release", "probe")[0], 0)
        self.assertEqual(self.h.rex.closed, [helper["block"]])
        self.assertIn(split, self.h.rex.blocks)
        self.assertEqual(self.h.run("release", helper["name"])[0], 0)
        self.assertEqual(self.h.run("release", helper["block"])[0], 0)
        self.assertEqual(self.h.watch("--timeout", "0"), (0, []))

    def test_release_after_the_block_closed(self) -> None:
        helper = self.h.start("probe")
        self.h.rex.gone(helper["block"])
        self.assertEqual(self.h.run("release", "probe")[0], 0)
        self.assertEqual(json.loads(self.h.run("ls", "--json")[1])[0]["state"], "released")


class LsTest(CommandTestCase):
    def test_states_and_json(self) -> None:
        starting = self.h.start("starting")
        working = self.h.start("working", "pi")
        done = self.h.start("done", "opencode")
        released = self.h.start("released")
        exited = self.h.start("exited")
        self.h.rex.set_status(working["block"], "working", "2026-01-01T00:00:00Z")
        self.h.rex.set_status(done["block"], "idle", "2026-01-01T00:00:00Z")
        self.h.write_result(done, age=5)  # Written while no watch ran.
        _ = self.h.run("release", released["name"])
        self.h.rex.exit(exited["block"], -1, "signal: killed")
        self.h.rex.blocks[starting["block"]].screen = "one\n\n two\n3\n4\n5\n6\n"

        status, out, err = self.h.run("ls", "--json")
        self.assertEqual(status, 0, err)
        rows = {row["name"]: row for row in json.loads(out)}
        self.assertEqual(
            {name.rsplit("-", 1)[0]: (r["state"], r["reason"]) for name, r in rows.items()},
            {
                "starting": ("starting", None),
                "working": ("working", None),
                "done": ("done", None),
                "released": ("released", None),
                "exited": ("exited", "signal killed"),
            },
        )
        self.assertEqual(rows[starting["name"]]["screen_tail"], [" two", "3", "4", "5", "6"])
        self.assertIsNone(rows[done["name"]]["screen_tail"])
        self.assertTrue(rows[done["name"]]["result_exists"])
        self.assertEqual(rows[working["name"]]["since"], "2026-01-01T00:00:00+00:00")
        self.assertIsNone(rows[exited["name"]]["since"])
        self.assertEqual(set(rows[done["name"]]), {
            "name", "harness", "block", "state", "reason", "since",
            "result", "result_exists", "screen_tail",
        })  # fmt: skip

        status, out, _ = self.h.run("ls")
        self.assertEqual(status, 0)
        self.assertIn(f"{exited['name']}  claude  {exited['block']}  exited signal killed", out)
        self.assertIn("    │ 6", out)

    def test_blocked_and_closed(self) -> None:
        blocked = self.h.start("blocked")
        closed = self.h.start("closed")
        self.h.rex.set_status(
            blocked["block"], "blocked", "t", kind="permission", msg="trust this folder"
        )
        self.h.rex.gone(closed["block"])
        rows = {r["name"]: r for r in json.loads(self.h.run("ls", "--json")[1])}
        self.assertEqual(
            (rows[blocked["name"]]["state"], rows[blocked["name"]]["reason"]),
            ("blocked", "permission: trust this folder"),
        )
        self.assertEqual(
            (rows[closed["name"]]["state"], rows[closed["name"]]["reason"]), ("exited", "closed")
        )

    def test_rex_failure_exits_1(self) -> None:
        _ = self.h.start("probe")
        self.h.rex.failing.add("process")
        status, _, err = self.h.run("ls")
        self.assertEqual(status, 1)
        self.assertIn("process failed", err)


if __name__ == "__main__":
    _ = unittest.main()
