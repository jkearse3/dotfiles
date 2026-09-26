"""Summarizing benchmark records as Markdown tables."""

from collections.abc import Callable, Iterable
from statistics import median

from .runner import RunRecord, time_estimate
from .session import Arm, SessionMetrics


def benchmark_report(records: list[RunRecord], baseline: list[RunRecord] | None = None) -> str:
    """Per-task medians for each arm, then each task's hashline-to-stock
    ratios, then totals by arm, over `records` and any `baseline` records
    standing in for an arm. Invalid runs are counted but left out."""
    reused: list[RunRecord] = baseline if baseline is not None else []
    valid = [record for record in [*records, *reused] if record.valid]
    invalid = len(records) + len(reused) - len(valid)
    tasks = sorted({record.task for record in valid})
    arms = [arm for arm in Arm if any(record.arm == arm for record in valid)]

    sections = [
        per_task_table(valid, tasks, arms),
        ratio_table(valid, tasks),
        arm_totals_table(valid, arms),
    ]
    if len(reused) > 0:
        sections.append(
            f"Stock results are reused from a baseline run ({len(reused)} session(s))."
        )
    if invalid > 0:
        sections.append(
            f"{invalid} invalid run(s) left out: their tools did not match "
            "their arm. See runs.jsonl."
        )
    return "\n\n".join(section for section in sections if section != "") + "\n"


# Each column reads one number from a session's metrics; None means unknown.
MetricColumn = tuple[str, Callable[[SessionMetrics], float | None]]

METRIC_COLUMNS: list[MetricColumn] = [
    ("turns", lambda metrics: metrics.num_turns),
    ("output tok", lambda metrics: metrics.output_tokens),
    ("seconds", lambda metrics: seconds(metrics.duration_ms)),
    ("cost $", lambda metrics: metrics.cost_usd),
    ("tool calls", lambda metrics: sum(metrics.tool_calls.values())),
    ("tool errors", lambda metrics: metrics.tool_errors),
    # In the hashline arm, shell calls are usually checks the tools' results
    # should have made unnecessary.
    ("shell calls", lambda metrics: metrics.tool_calls.get("Bash", 0)),
]


def per_task_table(records: list[RunRecord], tasks: list[str], arms: list[Arm]) -> str:
    header = ["task", "arm", "ok/n", *(f"median {name}" for name, _ in METRIC_COLUMNS)]
    rows: list[list[str]] = []
    for task in tasks:
        for arm in arms:
            group = [record for record in records if record.task == task and record.arm == arm]
            if len(group) == 0:
                continue
            successes = sum(record.success for record in group)
            medians = [
                format_number(median_of(read(record.metrics) for record in group))
                for _, read in METRIC_COLUMNS
            ]
            rows.append([task, arm, f"{successes}/{len(group)}", *medians])
    return markdown_table(header, rows)


def ratio_table(records: list[RunRecord], tasks: list[str]) -> str:
    """Hashline-to-stock ratios per task, below 1 meaning hashline used less:
    medians for turns, output tokens, and cost, and for time the ratio of
    means with its 90% interval and verdict, which decide when a task has
    run enough."""
    header = [
        "task",
        "success hashline vs stock",
        "turns ratio",
        "output tok ratio",
        "time ratio (90% CI)",
        "time verdict",
        "cost ratio",
    ]
    rows: list[list[str]] = []
    for task in tasks:
        hashline = [r for r in records if r.task == task and r.arm == Arm.HASHLINE]
        stock = [r for r in records if r.task == task and r.arm == Arm.STOCK]
        if len(hashline) == 0 or len(stock) == 0:
            continue
        rows.append(
            [
                task,
                f"{success_rate(hashline)} vs {success_rate(stock)}",
                format_ratio(median_ratio(hashline, stock, lambda m: m.num_turns)),
                format_ratio(median_ratio(hashline, stock, lambda m: m.output_tokens)),
                *time_columns(records, task),
                format_ratio(median_ratio(hashline, stock, lambda m: m.cost_usd)),
            ]
        )
    return markdown_table(header, rows) if len(rows) > 0 else ""


def time_columns(records: list[RunRecord], task: str) -> list[str]:
    estimate = time_estimate(records, task)
    if estimate is None:
        return ["-", "-"]
    interval = f"{estimate.ratio:.2f}x ({estimate.low:.2f}-{estimate.high:.2f})"
    return [interval, str(estimate.verdict)]


def arm_totals_table(records: list[RunRecord], arms: list[Arm]) -> str:
    """Each arm's success and spend, with turns, time, and cost summed over
    per-task means: tasks run different numbers of times, so raw totals
    would weight them unevenly."""
    header = [
        "arm",
        "runs",
        "success",
        "spent $",
        "turns per pass",
        "seconds per pass",
        "cost $ per pass",
    ]
    rows: list[list[str]] = []
    for arm in arms:
        group = [record for record in records if record.arm == arm]
        costs = [r.metrics.cost_usd for r in group if r.metrics.cost_usd is not None]
        rows.append(
            [
                arm,
                str(len(group)),
                success_rate(group),
                format_number(sum(costs)),
                format_number(sum_of_task_means(group, lambda m: m.num_turns)),
                format_number(sum_of_task_means(group, lambda m: seconds(m.duration_ms))),
                format_number(sum_of_task_means(group, lambda m: m.cost_usd)),
            ]
        )
    return markdown_table(header, rows)


def sum_of_task_means(
    records: list[RunRecord], read: Callable[[SessionMetrics], float | None]
) -> float | None:
    """The sum over tasks of each task's mean value, or None when any task
    has no known value."""
    total = 0.0
    for task in {record.task for record in records}:
        values = [read(r.metrics) for r in records if r.task == task]
        known = [value for value in values if value is not None]
        if len(known) == 0:
            return None
        total += sum(known) / len(known)
    return total


def median_ratio(
    numerator: list[RunRecord],
    denominator: list[RunRecord],
    read: Callable[[SessionMetrics], float | None],
) -> float | None:
    top = median_of(read(record.metrics) for record in numerator)
    bottom = median_of(read(record.metrics) for record in denominator)
    if top is None or bottom is None or bottom == 0:
        return None
    return top / bottom


def median_of(values: Iterable[float | None]) -> float | None:
    known = [value for value in values if value is not None]
    return median(known) if len(known) > 0 else None


def success_rate(records: list[RunRecord]) -> str:
    successes = sum(record.success for record in records)
    return f"{successes}/{len(records)}"


def seconds(duration_ms: int | None) -> float | None:
    return None if duration_ms is None else duration_ms / 1000


def format_number(value: float | None) -> str:
    if value is None:
        return "-"
    if value >= 100:
        return f"{value:,.0f}"
    return f"{value:.3g}"


def format_ratio(value: float | None) -> str:
    return "-" if value is None else f"{value:.2f}x"


def markdown_table(header: list[str], rows: list[list[str]]) -> str:
    lines = [header, ["---"] * len(header), *rows]
    return "\n".join("| " + " | ".join(line) + " |" for line in lines)
