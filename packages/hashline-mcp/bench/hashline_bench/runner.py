"""Scheduling benchmark sessions and recording each one's outcome."""

import json
import random
import shutil
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import cast

from .comparison import RatioEstimate, Verdict, compare_means
from .scoring import score_task, write_tree
from .session import Arm, SessionMetrics, SessionSettings, metrics_from_json, run_session
from .tasks import BenchTask


@dataclass(frozen=True)
class RunRecord:
    """One session's outcome, stored as a line of `runs.jsonl`.

    `valid` is False when the session's tools did not match its arm, such as
    a hashline session whose MCP server failed to start; reports leave such
    runs out.
    """

    run_id: str
    task: str
    arm: Arm
    repetition: int
    success: bool
    valid: bool
    mismatched_paths: list[str]
    answer_matches: bool | None
    metrics: SessionMetrics


RUNS_FILE = "runs.jsonl"
CONFIG_FILE = "config.json"


@dataclass(frozen=True)
class RunPlan:
    """What a benchmark run covers.

    Each task runs `min_runs` times in each of `arms`, then one more time
    per arm while its time comparison is unsure (see `undecided_tasks`), up
    to `max_runs`. `baseline` holds earlier records, normally stock's, that
    stand in for an arm this run leaves out. With `warmup`, each arm first
    runs one unrecorded session (see `warm_up`).
    """

    tasks: list[BenchTask]
    arms: list[Arm]
    min_runs: int
    max_runs: int
    baseline: list[RunRecord]
    warmup: bool = True


def run_benchmark(
    plan: RunPlan,
    settings: SessionSettings,
    out_dir: Path,
    jobs: int,
    seed: int,
) -> list[RunRecord]:
    """Run the sessions `plan` calls for, round by round, appending each
    record to `out_dir/runs.jsonl` as it finishes, and return this run's
    records.

    Each round is shuffled so neither arm consistently runs first.
    Transcripts go under `out_dir/transcripts`, and the working directory of
    any failed or invalid run is kept under `out_dir/failed` for inspection.
    """
    (out_dir / "transcripts").mkdir(parents=True, exist_ok=True)
    if plan.warmup:
        warm_up(plan.arms, settings, out_dir, jobs)
    lock = threading.Lock()
    records: list[RunRecord] = []
    scheduled = 0

    def run_one(task: BenchTask, arm: Arm, repetition: int) -> None:
        record = run_scheduled_session(task, arm, repetition, settings, out_dir)
        with lock:
            records.append(record)
            with (out_dir / RUNS_FILE).open("a") as runs:
                _ = runs.write(json.dumps(asdict(record)) + "\n")
            print(progress_line(record, len(records), scheduled), flush=True)

    schedule = [
        (task, arm, repetition)
        for task in plan.tasks
        for arm in plan.arms
        for repetition in range(1, plan.min_runs + 1)
    ]
    round_number = 0
    while len(schedule) > 0:
        random.Random(seed + round_number).shuffle(schedule)
        scheduled += len(schedule)
        with ThreadPoolExecutor(max_workers=jobs) as executor:
            futures = [executor.submit(run_one, *entry) for entry in schedule]
            for future in futures:
                future.result()

        round_number += 1
        schedule = [
            (task, arm, 1 + sum(r.task == task.name and r.arm == arm for r in records))
            for task in undecided_tasks(plan, records)
            for arm in plan.arms
        ]
    return records


def undecided_tasks(plan: RunPlan, records: list[RunRecord]) -> list[BenchTask]:
    """The tasks that need another round: those under `max_runs` whose time
    comparison is `UNSURE`, or that cannot be compared at all because an arm
    has no records, which therefore run `max_runs` times."""
    undecided: list[BenchTask] = []
    for task in plan.tasks:
        done = max(sum(r.task == task.name and r.arm == arm for r in records) for arm in plan.arms)
        if done >= plan.max_runs:
            continue
        estimate = time_estimate([*records, *plan.baseline], task.name)
        if estimate is None or estimate.verdict == Verdict.UNSURE:
            undecided.append(task)
    return undecided


def time_estimate(records: list[RunRecord], task: str) -> RatioEstimate | None:
    """Compare the wall time of `task`'s valid hashline and stock sessions."""

    def seconds(arm: Arm) -> list[float]:
        return [
            r.metrics.duration_ms / 1000
            for r in records
            if r.task == task and r.arm == arm and r.valid and r.metrics.duration_ms is not None
        ]

    return compare_means(seconds(Arm.HASHLINE), seconds(Arm.STOCK))


# Asks for no tool use, so a warm-up session is one short turn.
WARMUP_PROMPT = "Reply with the single word: ready."


def warm_up(arms: list[Arm], settings: SessionSettings, out_dir: Path, jobs: int) -> None:
    """Run one short session per arm and record nothing from it.

    Sessions share a cached prompt prefix, including the tool definitions,
    and the first sessions after those change pay to write that cache,
    which would inflate the first round's costs. Transcripts go to
    `out_dir/transcripts/warmup.<arm>.jsonl`.
    """

    def run_one(arm: Arm) -> None:
        work_dir = Path(tempfile.mkdtemp(prefix="hashline-bench-"))
        try:
            transcript = out_dir / "transcripts" / f"warmup.{arm}.jsonl"
            _ = run_session(settings, arm, WARMUP_PROMPT, work_dir, transcript)
        finally:
            shutil.rmtree(work_dir, ignore_errors=True)
        print(f"warmed up {arm}", flush=True)

    with ThreadPoolExecutor(max_workers=jobs) as executor:
        for future in [executor.submit(run_one, arm) for arm in arms]:
            future.result()


def run_scheduled_session(
    task: BenchTask,
    arm: Arm,
    repetition: int,
    settings: SessionSettings,
    out_dir: Path,
) -> RunRecord:
    run_id = f"{task.name}.{arm}.{repetition}"
    work_dir = Path(tempfile.mkdtemp(prefix="hashline-bench-"))
    try:
        write_tree(work_dir, task.before)
        transcript = out_dir / "transcripts" / f"{run_id}.jsonl"
        metrics = run_session(settings, arm, task.prompt, work_dir, transcript)
        score = score_task(task, work_dir, metrics.final_text)

        record = RunRecord(
            run_id=run_id,
            task=task.name,
            arm=arm,
            repetition=repetition,
            success=score.success,
            valid=metrics.hashline_loaded == (arm == Arm.HASHLINE),
            mismatched_paths=score.mismatched_paths,
            answer_matches=score.answer_matches,
            metrics=metrics,
        )
        if not (record.success and record.valid):
            _ = shutil.copytree(work_dir, out_dir / "failed" / run_id)
        return record
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


def progress_line(record: RunRecord, done: int, total: int) -> str:
    if not record.valid:
        outcome = "INVALID"
    elif record.success:
        outcome = "ok"
    else:
        outcome = "FAIL"
    metrics = record.metrics
    cost = "-" if metrics.cost_usd is None else f"${metrics.cost_usd:.3f}"
    return (
        f"[{done}/{total} so far] {record.run_id}: {outcome}, "
        f"{metrics.output_tokens} output tokens, {cost}"
    )


def load_records(out_dir: Path) -> list[RunRecord]:
    """Read the records a benchmark run appended to `out_dir/runs.jsonl`."""
    records: list[RunRecord] = []
    for line in (out_dir / RUNS_FILE).read_text().splitlines():
        if line.strip() == "":
            continue
        # Written by `run_benchmark` from `asdict`, so the shape is known.
        fields = cast(dict[str, object], json.loads(line))
        records.append(
            RunRecord(
                run_id=str(fields["run_id"]),
                task=str(fields["task"]),
                arm=Arm(str(fields["arm"])),
                repetition=cast(int, fields["repetition"]),
                success=fields["success"] is True,
                valid=fields["valid"] is True,
                mismatched_paths=cast(list[str], fields["mismatched_paths"]),
                answer_matches=cast(bool | None, fields["answer_matches"]),
                metrics=metrics_from_json(cast(dict[str, object], fields["metrics"])),
            )
        )
    return records


class BaselineError(Exception):
    """A baseline run that cannot stand in for this one."""


def load_baseline(baseline_dir: Path, tasks: list[BenchTask]) -> list[RunRecord]:
    """Return the stock records of `tasks` from an earlier run in
    `baseline_dir`.

    Raises `BaselineError` when the run's `config.json` records no task
    digests, or when any task is missing from it or has changed since, since
    stock results for a different task would skew every comparison.
    """
    config = cast(dict[str, object], json.loads((baseline_dir / CONFIG_FILE).read_text()))
    digests = config.get("task_digests")
    if not isinstance(digests, dict):
        raise BaselineError(f"{baseline_dir} records no task digests; run stock again")
    recorded = cast(dict[str, object], digests)
    stale = [task.name for task in tasks if recorded.get(task.name) != task.digest()]
    if len(stale) > 0:
        raise BaselineError(
            f"{baseline_dir} lacks or predates these tasks: {', '.join(stale)}; run stock again"
        )

    names = {task.name for task in tasks}
    return [r for r in load_records(baseline_dir) if r.arm == Arm.STOCK and r.task in names]
