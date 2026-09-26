import contextlib
import io
import json
import sys
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from hashline_bench.__main__ import main
from hashline_bench.comparison import Verdict, compare_means
from hashline_bench.report import benchmark_report
from hashline_bench.runner import RunPlan, load_records, run_benchmark
from hashline_bench.scoring import score_task, write_tree
from hashline_bench.session import Arm, SessionSettings, parse_transcript
from hashline_bench.tasks import CORE_TASK_NAMES, bench_tasks

# Stands in for `claude -p`: it edits nothing, reports the tools its arm
# would load, makes one failing tool call, and answers "45".
FAKE_CLAUDE = """
import json, os, pathlib
hashline = os.environ["CLAUDE_HASHLINE"] == "1"
# How many sessions of this arm ran before this one.
counter = pathlib.Path(COUNTER_DIR) / ("count-hashline" if hashline else "count-stock")
count = int(counter.read_text()) if counter.exists() else 0
_ = counter.write_text(str(count + 1))
tools = ["Read", "Edit"] + (["mcp__hashline__read"] if hashline else [])
events = [
    {"type": "system", "subtype": "init", "tools": tools},
    {"type": "assistant", "message": {"content": [
        {"type": "text", "text": "Looking."},
        {"type": "tool_use", "name": "Read", "input": {}},
    ]}},
    {"type": "user", "message": {"content": [
        {"type": "tool_result", "is_error": True, "content": "no"},
    ]}},
    {"type": "result", "subtype": "success", "is_error": False,
     "num_turns": 2, "duration_ms": DURATION, "total_cost_usd": 0.25, "result": "45",
     "usage": {"input_tokens": 10, "output_tokens": 30,
               "cache_read_input_tokens": 5, "cache_creation_input_tokens": 7}},
]
for event in events:
    print(json.dumps(event))
"""



def fake_claude(directory: Path, duration: str = "1500") -> Path:
    """Write an executable fake `claude` whose sessions take `duration`
    milliseconds, a Python expression that may use `count`, the number of
    earlier sessions in the same arm."""
    fake = directory / "fake_claude"
    script = FAKE_CLAUDE.replace("DURATION", duration).replace("COUNTER_DIR", repr(str(directory)))
    _ = fake.write_text(f"#!{sys.executable}\n" + script)
    fake.chmod(0o755)
    return fake


def fake_settings(fake: Path) -> SessionSettings:
    return SessionSettings(
        claude_command=[str(fake)],
        model=None,
        effort=None,
        max_budget_usd=1.0,
        timeout_seconds=60,
    )


def plan(
    tasks: list[str], arms: list[Arm], min_runs: int, max_runs: int, warmup: bool = True
) -> RunPlan:
    return RunPlan(
        tasks=[task for task in bench_tasks() if task.name in tasks],
        arms=arms,
        min_runs=min_runs,
        max_runs=max_runs,
        baseline=[],
        warmup=warmup,
    )


class BenchTaskTest(unittest.TestCase):
    def test_tasks_are_unique_and_only_the_control_leaves_files_alone(self) -> None:
        tasks = bench_tasks()
        names = [task.name for task in tasks]

        self.assertEqual(len(names), len(set(names)))
        for task in tasks:
            with self.subTest(task=task.name):
                self.assertEqual(task.before == task.after, task.answer is not None)

    def test_core_tasks_exist_and_digests_follow_the_task(self) -> None:
        tasks = bench_tasks()
        task = tasks[0]

        self.assertLessEqual(CORE_TASK_NAMES, {task.name for task in tasks})
        self.assertEqual(task.digest(), bench_tasks()[0].digest())
        self.assertNotEqual(task.digest(), replace(task, prompt=task.prompt + " ").digest())

    def test_byte_level_tasks_keep_their_encoding_in_the_expected_result(self) -> None:
        tasks = {task.name: task for task in bench_tasks()}
        crlf = tasks["crlf-line-endings"].after["legacy.ini"]
        notes = tasks["bom-without-final-newline"].after["notes.md"]

        self.assertEqual(crlf.count(b"\n"), crlf.count(b"\r\n"))
        self.assertIn(b"timeout_seconds = 90\r\n", crlf)
        self.assertTrue(notes.startswith("﻿".encode()))
        self.assertFalse(notes.endswith(b"\n"))

    def test_rename_leaves_names_that_contain_the_old_name(self) -> None:
        task = next(task for task in bench_tasks() if task.name == "rename-across-files")
        store = task.after["store.py"].decode()

        self.assertIn("def load_record(", store)
        self.assertIn("def fetch_record_count(", store)
        self.assertIn("def prefetch_record_cache(", store)
        self.assertNotIn("fetch_record(", "".join(t.decode() for t in task.after.values()))


class ScoreTaskTest(unittest.TestCase):
    def test_reports_changed_created_and_ignored_paths(self) -> None:
        task = next(task for task in bench_tasks() if task.name == "one-line-in-large-file")
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            write_tree(root, task.after)
            write_tree(root, {"__pycache__/handlers.cpython-313.pyc": b"x"})
            self.assertTrue(score_task(task, root, None).success)

            write_tree(root, {"extra.txt": b"", "handlers.py": task.before["handlers.py"]})
            score = score_task(task, root, None)

        self.assertEqual(score.mismatched_paths, ["extra.txt", "handlers.py"])
        self.assertFalse(score.success)

    def test_answer_must_appear_as_a_whole_word(self) -> None:
        task = bench_tasks()[0]
        assert task.answer is not None
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            write_tree(root, task.after)

            self.assertTrue(score_task(task, root, f"There are {task.answer}.").success)
            self.assertFalse(score_task(task, root, f"{task.answer}0").success)
            self.assertFalse(score_task(task, root, None).success)


class ParseTranscriptTest(unittest.TestCase):
    def test_skips_lines_that_are_not_json_objects(self) -> None:
        metrics = parse_transcript('not json\n[1]\n{"type": "result", "num_turns": 3}\n')

        self.assertEqual(metrics.num_turns, 3)
        self.assertIsNone(metrics.hashline_loaded)
        self.assertIsNone(metrics.cost_usd)


class RunBenchmarkTest(unittest.TestCase):
    def test_runs_every_arm_records_metrics_and_keeps_failed_work(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            out_dir = Path(raw) / "out"
            settings = fake_settings(fake_claude(Path(raw)))

            # Equal times decide every comparison after the minimum runs.
            records = run_benchmark(
                plan(["read-only-control", "one-line-in-large-file"], list(Arm), 2, 4),
                settings,
                out_dir,
                jobs=2,
                seed=1,
            )
            loaded = load_records(out_dir)
            failed = sorted(path.name for path in (out_dir / "failed").iterdir())
            transcript = (out_dir / "transcripts" / "read-only-control.stock.1.jsonl").read_text()
            warmups = sorted(path.name for path in (out_dir / "transcripts").glob("warmup.*.jsonl"))

        # One unrecorded warm-up session per arm runs first.
        self.assertEqual(warmups, ["warmup.hashline.jsonl", "warmup.stock.jsonl"])
        self.assertEqual(len(records), 8)
        self.assertEqual({r.run_id: r for r in records}, {r.run_id: r for r in loaded})
        outcomes = {(r.task, r.arm): (r.success, r.valid) for r in loaded}
        self.assertEqual(
            outcomes,
            {
                ("read-only-control", Arm.HASHLINE): (True, True),
                ("read-only-control", Arm.STOCK): (True, True),
                ("one-line-in-large-file", Arm.HASHLINE): (False, True),
                ("one-line-in-large-file", Arm.STOCK): (False, True),
            },
        )
        self.assertEqual(
            failed,
            [
                "one-line-in-large-file.hashline.1",
                "one-line-in-large-file.hashline.2",
                "one-line-in-large-file.stock.1",
                "one-line-in-large-file.stock.2",
            ],
        )
        self.assertIn('"result": "45"', transcript.splitlines()[-1])

        metrics = loaded[0].metrics
        self.assertEqual(metrics.exit_code, 0)
        self.assertEqual(metrics.output_tokens, 30)
        self.assertEqual(metrics.cache_creation_tokens, 7)
        self.assertEqual(metrics.tool_calls, {"Read": 1})
        self.assertEqual(metrics.tool_errors, 1)

        report = benchmark_report(loaded)
        self.assertIn("| read-only-control | hashline | 2/2 | 2 | 30 | 1.5 | 0.25 | 1 | 1 | 0 |", report)
        self.assertIn(
            "| one-line-in-large-file | 0/2 vs 0/2 | 1.00x | 1.00x | 1.00x (1.00-1.00) | equivalent | 1.00x |",
            report,
        )
        self.assertIn("| hashline | 4 | 2/4 | 1 | 4 | 3 | 0.5 |", report)

    def test_unsure_tasks_run_until_the_most_runs(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            # Alternating times keep every comparison unsure.
            settings = fake_settings(fake_claude(Path(raw), "[1000, 9000][count % 2]"))
            records = run_benchmark(
                plan(["read-only-control"], list(Arm), 2, 4, warmup=False),
                settings,
                Path(raw) / "out",
                1,
                0,
            )
            warmed = (Path(raw) / "out" / "transcripts" / "warmup.stock.jsonl").exists()

        counts = {arm: sum(r.arm == arm for r in records) for arm in Arm}
        self.assertEqual(counts, {Arm.HASHLINE: 4, Arm.STOCK: 4})
        self.assertFalse(warmed)

    def test_a_baseline_replaces_the_stock_arm_until_its_tasks_change(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            fake = str(fake_claude(Path(raw)))
            common = ["run", "--claude", fake, "--task", "read-only-control", "--runs", "2", "--min-runs", "2"]
            stock_dir, hashline_dir = Path(raw) / "stock", Path(raw) / "hashline"
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main([*common, "--arm", "stock", "--out", str(stock_dir)]), 0)
                self.assertEqual(
                    main([*common, "--baseline", str(stock_dir), "--out", str(hashline_dir)]), 0
                )
            arms = {record.arm for record in load_records(hashline_dir)}
            report = (hashline_dir / "report.md").read_text()

            config_path = stock_dir / "config.json"
            config = json.loads(config_path.read_text())
            config["task_digests"]["read-only-control"] = "stale"
            _ = config_path.write_text(json.dumps(config))
            with contextlib.redirect_stderr(io.StringIO()) as errors:
                refused = main([*common, "--baseline", str(stock_dir), "--out", str(Path(raw) / "x")])

        self.assertEqual(arms, {Arm.HASHLINE})
        self.assertIn("reused from a baseline run (2 session(s))", report)
        self.assertIn("| read-only-control | 2/2 vs 2/2 |", report)
        self.assertEqual(refused, 2)
        self.assertIn("predates these tasks: read-only-control", errors.getvalue())

    def test_a_session_without_its_arms_tools_is_invalid(self) -> None:
        task = bench_tasks()[0]
        with tempfile.TemporaryDirectory() as raw:
            out_dir = Path(raw) / "out"
            fake = Path(raw) / "fake_claude"
            _ = fake.write_text(
                f"#!{sys.executable}\n"
                + FAKE_CLAUDE.replace("DURATION", "1500")
                .replace("COUNTER_DIR", repr(raw))
                .replace('== "1"', '== "never"')
            )
            fake.chmod(0o755)
            only = RunPlan(tasks=[task], arms=[Arm.HASHLINE], min_runs=2, max_runs=2, baseline=[])

            [record, _] = run_benchmark(only, fake_settings(fake), out_dir, 1, 0)

        self.assertFalse(record.valid)
        self.assertIn("1 invalid run(s) left out", benchmark_report([record]))


class CompareMeansTest(unittest.TestCase):
    def test_verdicts(self) -> None:
        cases = [
            ([5.0, 5.2, 4.8], [10.0, 10.4, 9.6], Verdict.LOWER),
            ([10.0, 10.4, 9.6], [5.0, 5.2, 4.8], Verdict.HIGHER),
            ([10.0, 10.1, 9.9], [10.0, 10.2, 9.8], Verdict.EQUIVALENT),
            ([5.0, 15.0, 9.0], [10.0, 6.0, 12.0], Verdict.UNSURE),
        ]
        for hashline, stock, verdict in cases:
            with self.subTest(verdict=verdict):
                estimate = compare_means(hashline, stock)
                assert estimate is not None
                self.assertEqual(estimate.verdict, verdict)
                self.assertLessEqual(estimate.low, estimate.ratio)
                self.assertLessEqual(estimate.ratio, estimate.high)

    def test_needs_two_values_per_arm(self) -> None:
        self.assertIsNone(compare_means([1.0], [1.0, 2.0]))


if __name__ == "__main__":
    _ = unittest.main()
