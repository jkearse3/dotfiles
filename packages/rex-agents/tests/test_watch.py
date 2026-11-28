"""Tests for `rex-agents watch`."""

from __future__ import annotations

import unittest
from collections.abc import Callable
from typing import override

from rex_agents.store import Store
from tests.fakes import PARENT, Harness, StartedHelper, StopWatch


class WatchTestCase(unittest.TestCase):
    @override
    def setUp(self) -> None:
        self.h = Harness()
        self.addCleanup(self.h.cleanup)

    def watch(
        self, *argv: str, hooks: dict[int, Callable[[], None]] | None = None
    ) -> tuple[int, list[str]]:
        """Run watch with HOOKS keyed by the Nth sleep of this run."""
        self.h.clock.sleeps = 0
        self.h.clock.hooks = hooks if hooks is not None else {}
        return self.h.watch(*argv)

    def line(self, helper: StartedHelper, news: str) -> str:
        return f"{helper['block']} {helper['name']} {news}"


class LinesTest(WatchTestCase):
    def test_result_file_and_turn_end_in_one_check_print_one_done(self) -> None:
        helper = self.h.start()
        self.h.rex.set_status(helper["block"], "working", "t1")
        self.assertEqual(self.watch("--timeout", "0"), (0, []))

        def finish() -> None:
            self.h.write_result(helper, age=0.5)  # Younger than one interval.
            self.h.rex.set_status(helper["block"], "done", "t2")

        status, lines = self.watch("--timeout", "10", hooks={1: finish})
        self.assertEqual(status, 0)
        self.assertEqual(lines, [self.line(helper, "done"), f"{PARENT} watch-ended"])
        self.assertEqual(self.h.rex.label(helper["block"]), f"✓ {helper['name']}")

    def test_result_written_while_no_run_was_active(self) -> None:
        helper = self.h.start()
        self.h.rex.set_status(helper["block"], "done", "t1")
        self.h.write_result(helper)
        self.assertEqual(self.watch("--timeout", "0"), (0, [self.line(helper, "done")]))
        self.assertEqual(self.watch("--timeout", "0"), (0, []))

    def test_result_edited_while_working_waits_for_the_turn(self) -> None:
        helper = self.h.start()
        self.h.rex.set_status(helper["block"], "working", "t1")
        self.h.write_result(helper)
        self.assertEqual(self.watch("--timeout", "0"), (0, []))
        self.h.write_result(helper, "more\n")
        self.assertEqual(self.watch("--timeout", "0"), (0, []))
        self.h.rex.set_status(helper["block"], "done", "t2")
        self.assertEqual(self.watch("--timeout", "0"), (0, [self.line(helper, "done")]))

    def test_turn_without_result_then_result_prints_two_dones(self) -> None:
        helper = self.h.start()
        self.h.rex.set_status(helper["block"], "done", "t1")
        self.assertEqual(self.watch("--timeout", "0"), (0, [self.line(helper, "done")]))
        self.assertEqual(self.h.rex.label(helper["block"]), helper["name"])
        self.h.write_result(helper)
        self.assertEqual(self.watch("--timeout", "0"), (0, [self.line(helper, "done")]))
        self.assertEqual(self.watch("--timeout", "0"), (0, []))

    def test_result_then_exit_prints_done_then_exited_without_cross(self) -> None:
        helper = self.h.start()
        self.h.write_result(helper, age=0)
        self.h.rex.exit(helper["block"], 1, "exit status 1")
        self.assertEqual(
            self.watch("--timeout", "0"),
            (0, [self.line(helper, "done"), self.line(helper, "exited 1")]),
        )
        self.assertEqual(self.h.rex.label(helper["block"]), f"✓ {helper['name']}")

    def test_exits(self) -> None:
        code = self.h.start("code")
        signal = self.h.start("signal")
        clean = self.h.start("clean")
        closed = self.h.start("closed")
        self.h.rex.exit(code["block"], 3, "exit status 3")
        self.h.rex.exit(signal["block"], -1, "signal: killed")
        self.h.rex.exit(clean["block"], 0)
        self.h.rex.gone(closed["block"])
        status, lines = self.watch("--timeout", "0")
        self.assertEqual(status, 0)
        self.assertEqual(
            lines,
            [
                self.line(code, "exited 3"),
                self.line(signal, "exited signal killed"),
                self.line(clean, "exited 0"),
                self.line(closed, "exited closed"),
            ],
        )
        self.assertEqual(self.h.rex.label(code["block"]), f"✗ {code['name']}")
        self.assertEqual(self.h.rex.label(signal["block"]), f"✗ {signal['name']}")
        self.assertEqual(self.h.rex.label(clean["block"]), clean["name"])
        self.assertEqual(self.watch("--timeout", "0"), (0, []))

    def test_opencode_turn_within_one_check_prints_one_fallback_done(self) -> None:
        helper = self.h.start(harness="opencode")
        self.h.rex.set_status(helper["block"], "idle", "2026-01-01T00:00:00Z")
        self.assertEqual(self.watch("--timeout", "0"), (0, []))  # Startup idle.
        self.h.rex.set_status(helper["block"], "idle", "2026-01-01T00:00:05Z")
        self.assertEqual(self.watch("--timeout", "0"), (0, [self.line(helper, "done")]))
        self.assertEqual(self.watch("--timeout", "0"), (0, []))

    def test_idle_after_working_is_a_turn_end(self) -> None:
        helper = self.h.start(harness="pi")
        self.h.rex.set_status(helper["block"], "working", "t1")
        _ = self.watch("--timeout", "0")
        self.h.rex.set_status(helper["block"], "idle", "t1")
        self.assertEqual(self.watch("--timeout", "0"), (0, [self.line(helper, "done")]))

    def test_blocked_and_error_reasons(self) -> None:
        helper = self.h.start()
        self.h.rex.set_status(
            helper["block"], "blocked", "t1", kind="permission", msg="trust\n  this\tfolder"
        )
        self.assertEqual(
            self.watch("--timeout", "0"),
            (0, [self.line(helper, "blocked permission: trust this folder")]),
        )
        self.assertEqual(self.watch("--timeout", "0"), (0, []))
        self.h.rex.set_status(helper["block"], "blocked", "t2", kind="permission", msg="x" * 200)
        _, lines = self.watch("--timeout", "0")
        self.assertEqual(lines, [self.line(helper, "blocked " + ("permission: " + "x" * 200)[:120])])
        self.h.rex.set_status(helper["block"], "error", "t3")
        self.assertEqual(self.watch("--timeout", "0"), (0, [self.line(helper, "error")]))

    def test_blocked_record_wins_over_the_root(self) -> None:
        helper = self.h.start()
        self.h.rex.blocks[helper["block"]].records = [
            {"state": "working", "updated_at": "t"},
            {"id": "sub", "state": "blocked", "updated_at": "t", "msg": "run ls?"},
        ]
        self.assertEqual(
            self.watch("--timeout", "0"), (0, [self.line(helper, "blocked run ls?")])
        )

    def test_released_helpers_are_not_reported(self) -> None:
        helper = self.h.start()
        _ = self.h.run("release", "probe")
        self.assertEqual(self.watch("--timeout", "0"), (0, []))

    def test_release_during_a_check_is_not_reported_as_exited(self) -> None:
        helper = self.h.start()
        store = Store(self.h.root / "state" / "rex-agents", PARENT)
        process = self.h.rex.process

        def release_then_answer(block: str) -> dict[str, object]:
            store.release(block, 0)
            self.h.rex.gone(block)
            return process(block)

        self.h.rex.process = release_then_answer  # type: ignore[method-assign]
        self.assertEqual(self.watch("--timeout", "0"), (0, []))


class RunTest(WatchTestCase):
    def test_until_news_exits_after_a_line(self) -> None:
        helper = self.h.start()

        def finish() -> None:
            self.h.rex.set_status(helper["block"], "done", "t1")

        status, lines = self.watch("--until-news", hooks={3: finish})
        self.assertEqual((status, lines), (0, [self.line(helper, "done")]))
        self.assertEqual(self.h.clock.sleeps, 3)

    def test_watch_ends_at_the_default_timeout(self) -> None:
        _ = self.h.start()
        self.h.clock.max_sleeps = 1000
        status, lines = self.watch()
        self.assertEqual((status, lines), (0, [f"{PARENT} watch-ended"]))
        self.assertEqual(self.h.clock.sleeps, 720)

    def test_exits_quietly_without_live_helpers(self) -> None:
        self.assertEqual(self.watch(), (0, []))
        helper = self.h.start()
        self.h.rex.exit(helper["block"], 0)
        self.assertEqual(self.watch(), (0, [self.line(helper, "exited 0")]))
        self.assertEqual(self.h.clock.sleeps, 0)

    def test_failed_rex_call(self) -> None:
        _ = self.h.start()
        self.h.rex.failing.add("program_status")
        status, lines = self.watch("--timeout", "0")
        self.assertEqual((status, lines), (1, [f"{PARENT} watch-failed program_status failed"]))

    def test_unreadable_registry(self) -> None:
        _ = self.h.start()
        registry = self.h.root / "state" / "rex-agents" / "parents" / PARENT / "registry.jsonl"
        _ = registry.write_text("not json\n")
        status, lines = self.watch("--timeout", "0")
        self.assertEqual(status, 1)
        self.assertTrue(lines[0].startswith(f"{PARENT} watch-failed "))

    def test_failed_relabel_prints_nothing(self) -> None:
        helper = self.h.start()
        self.h.write_result(helper)
        self.h.rex.failing.add("rename_tab")
        self.assertEqual(self.watch("--timeout", "0"), (0, [self.line(helper, "done")]))

    def test_second_run_defers_and_the_first_picks_up_new_helpers(self) -> None:
        first = self.h.start("one")
        results: list[tuple[int, list[str]]] = []
        second: list[StartedHelper] = []

        def register_and_watch_again() -> None:
            self.h.clock.time += 1
            second.append(self.h.start("two"))
            results.append(self.h.watch("--timeout", "0"))

        def finish_second() -> None:
            self.h.rex.set_status(second[0]["block"], "done", "t1")

        thread_hooks = {1: register_and_watch_again, 2: finish_second}
        status, lines = self.watch("--until-news", hooks=thread_hooks)
        self.assertEqual(results, [(0, [f"{PARENT} watch-already-running"])])
        self.assertEqual((status, lines), (0, [self.line(second[0], "done")]))
        self.assertTrue(first)

    def test_lock_is_freed_when_a_run_ends(self) -> None:
        _ = self.h.start()
        self.assertEqual(self.watch("--timeout", "0"), (0, []))
        self.assertIsNotNone(Store(self.h.root / "state" / "rex-agents", PARENT).try_lock())

    def test_an_interrupted_run_frees_the_lock(self) -> None:
        _ = self.h.start()
        self.h.clock.max_sleeps = 1
        with self.assertRaises(StopWatch):
            _ = self.watch()
        self.assertEqual(self.watch("--timeout", "0"), (0, []))

    def test_concurrent_runs_one_watches(self) -> None:
        _ = self.h.start()
        store = Store(self.h.root / "state" / "rex-agents", PARENT)
        held = store.try_lock()
        assert held is not None
        try:
            self.assertEqual(self.watch(), (0, [f"{PARENT} watch-already-running"]))
        finally:
            held.release()


if __name__ == "__main__":
    _ = unittest.main()
