"""Command line: `run` a benchmark, `report` on a finished one, or list `tasks`."""

import argparse
import json
import os
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import cast

from .report import benchmark_report
from .runner import (
    CONFIG_FILE,
    BaselineError,
    RunPlan,
    RunRecord,
    load_baseline,
    load_records,
    run_benchmark,
)
from .session import Arm, SessionSettings
from .tasks import CORE_TASK_NAMES, bench_tasks


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="hashline_bench",
        description="Compare hashline editing with Claude Code's stock file tools.",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    run = commands.add_parser("run", help="run sessions and report on them")
    _ = run.add_argument(
        "--runs", type=int, default=5, help="most repetitions per task and arm"
    )
    _ = run.add_argument(
        "--min-runs",
        type=int,
        default=3,
        help="repetitions before a task stops once its time comparison is decided",
    )
    _ = run.add_argument(
        "--task", action="append", help="run only this task (repeatable); see `tasks`"
    )
    _ = run.add_argument(
        "--arm", action="append", choices=[arm.value for arm in Arm], help="repeatable"
    )
    _ = run.add_argument(
        "--all-tasks", action="store_true", help="include tasks outside the core set"
    )
    _ = run.add_argument(
        "--baseline",
        type=Path,
        help="reuse stock results from this earlier run and run only hashline",
    )
    _ = run.add_argument(
        "--no-warmup",
        action="store_true",
        help="skip the unrecorded session per arm that warms the prompt cache",
    )
    _ = run.add_argument("--model", help="passed to claude --model")
    _ = run.add_argument("--effort", help="passed to claude --effort")
    _ = run.add_argument(
        "--max-budget-usd", type=float, default=2.0, help="spend cap per session"
    )
    _ = run.add_argument("--timeout", type=int, default=900, help="seconds per session")
    _ = run.add_argument("--jobs", type=int, default=1, help="sessions run at once")
    _ = run.add_argument("--seed", type=int, default=0, help="schedule shuffle seed")
    _ = run.add_argument("--out", type=Path, help="results directory")
    _ = run.add_argument(
        "--claude", default="claude", help="claude executable (default: claude on PATH)"
    )

    report = commands.add_parser("report", help="summarize a finished run")
    _ = report.add_argument("out", type=Path, help="results directory of a run")

    _ = commands.add_parser("tasks", help="list task names and prompts")

    args = parser.parse_args(argv)
    match args.command:
        case "run":
            return command_run(args)
        case "report":
            print(benchmark_report(load_records(args.out), recorded_baseline(args.out)), end="")
            return 0
        case _:
            for task in bench_tasks():
                core = "" if task.name in CORE_TASK_NAMES else " (not in the core set)"
                print(f"{task.name}{core}\n    {task.prompt}")
            return 0


def command_run(args: argparse.Namespace) -> int:
    tasks = bench_tasks()
    if args.task:
        unknown = set(args.task) - {task.name for task in tasks}
        if len(unknown) > 0:
            print(f"unknown task(s): {', '.join(sorted(unknown))}", file=sys.stderr)
            return 2
        tasks = [task for task in tasks if task.name in args.task]
    elif not args.all_tasks:
        tasks = [task for task in tasks if task.name in CORE_TASK_NAMES]
    if not 2 <= args.min_runs <= args.runs:
        print("--min-runs must be at least 2 and at most --runs", file=sys.stderr)
        return 2

    baseline: list[RunRecord] = []
    if args.baseline is not None:
        if args.arm and Arm.STOCK.value in args.arm:
            print("--baseline replaces the stock arm; leave it out of --arm", file=sys.stderr)
            return 2
        try:
            baseline = load_baseline(args.baseline, tasks)
        except (BaselineError, OSError) as error:
            print(f"cannot use the baseline: {error}", file=sys.stderr)
            return 2
    if args.arm:
        arms = [Arm(arm) for arm in args.arm]
    elif args.baseline is not None:
        arms = [Arm.HASHLINE]
    else:
        arms = list(Arm)

    settings = SessionSettings(
        claude_command=[args.claude],
        model=args.model,
        effort=args.effort,
        max_budget_usd=args.max_budget_usd,
        timeout_seconds=args.timeout,
    )
    out_dir: Path = args.out or default_out_dir()
    baseline_dir: Path | None = args.baseline
    out_dir.mkdir(parents=True, exist_ok=True)
    config = {
        "tasks": [task.name for task in tasks],
        "arms": [str(arm) for arm in arms],
        "runs": args.runs,
        "min_runs": args.min_runs,
        "warmup": not args.no_warmup,
        "baseline": None if baseline_dir is None else str(baseline_dir.resolve()),
        "task_digests": {task.name: task.digest() for task in tasks},
        "model": args.model,
        "effort": args.effort,
        "max_budget_usd": args.max_budget_usd,
        "seed": args.seed,
    }
    _ = (out_dir / CONFIG_FILE).write_text(json.dumps(config, indent=2) + "\n")
    print(f"results: {out_dir}", flush=True)

    plan = RunPlan(
        tasks=tasks,
        arms=arms,
        min_runs=args.min_runs,
        max_runs=args.runs,
        baseline=baseline,
        warmup=not args.no_warmup,
    )
    records = run_benchmark(plan, settings, out_dir, args.jobs, args.seed)
    report = benchmark_report(records, baseline)
    _ = (out_dir / "report.md").write_text(report)
    print("\n" + report, end="")
    return 0


def recorded_baseline(out_dir: Path) -> list[RunRecord]:
    """The baseline records a finished run in `out_dir` compared against, or
    none when it ran without a baseline."""
    config = cast(dict[str, object], json.loads((out_dir / CONFIG_FILE).read_text()))
    baseline = config.get("baseline")
    if not isinstance(baseline, str):
        return []
    tasks = [task for task in bench_tasks() if task.name in cast(list[str], config["tasks"])]
    return load_baseline(Path(baseline), tasks)


def default_out_dir() -> Path:
    """A fresh timestamped directory under the XDG state directory, outside
    the repository, since transcripts are large and specific to one run."""
    state_home = os.environ.get("XDG_STATE_HOME", "")
    if state_home == "":
        state_home = str(Path.home() / ".local/state")
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    return Path(state_home) / "hashline-bench" / stamp


if __name__ == "__main__":
    sys.exit(main())
