"""One headless Claude Code session, and the metrics read from its transcript.

A session runs `claude -p` with `--output-format stream-json`, which writes
one JSON event per line: an `init` event listing the session's tools,
`assistant` and `user` messages carrying tool calls and their results, and a
final `result` event with turn, duration, cost, and token totals.
"""

import json
import os
import subprocess
from collections import Counter
from dataclasses import dataclass, field
from enum import StrEnum
from pathlib import Path
from typing import cast


class Arm(StrEnum):
    """Which editing tools a session gets.

    The `claude` wrapper reads `CLAUDE_HASHLINE`: `0` launches without the
    hashline MCP server, and the CLAUDE.md hashline rule applies only when its
    tools are present, so the stock arm is Claude Code as it ships.
    """

    HASHLINE = "hashline"
    STOCK = "stock"


@dataclass(frozen=True)
class SessionSettings:
    """Launch options shared by every session of a benchmark run.

    `claude_command` is the executable and any leading arguments. `model` and
    `effort` are passed through when set; otherwise the user's settings
    decide. `max_budget_usd` caps one session's spend, and `timeout_seconds`
    kills a session that runs longer.
    """

    claude_command: list[str]
    model: str | None
    effort: str | None
    max_budget_usd: float
    timeout_seconds: int


@dataclass
class SessionMetrics:
    """What one session cost and did, read from its stream-json transcript.

    Fields the transcript lacks stay None, as when a session is killed before
    its `result` event. `hashline_loaded` is None when there was no `init`
    event to check.
    """

    exit_code: int | None = None
    timed_out: bool = False
    result_subtype: str | None = None
    is_error: bool | None = None
    num_turns: int | None = None
    duration_ms: int | None = None
    cost_usd: float | None = None
    input_tokens: int | None = None
    output_tokens: int | None = None
    cache_read_tokens: int | None = None
    cache_creation_tokens: int | None = None
    tool_calls: dict[str, int] = field(default_factory=dict)
    tool_errors: int = 0
    hashline_loaded: bool | None = None
    final_text: str | None = None


HASHLINE_TOOL_PREFIX = "mcp__hashline__"


def run_session(
    settings: SessionSettings,
    arm: Arm,
    prompt: str,
    work_dir: Path,
    transcript: Path,
) -> SessionMetrics:
    """Run one headless session in `work_dir`, saving its stdout to
    `transcript` and its stderr beside it with a `.stderr` suffix.

    Uses auto permission mode with prompts denied, as an unattended
    interactive session would behave. `--strict-mcp-config` keeps other MCP
    servers, such as claude.ai connectors that attach to some sessions and not
    others, from adding tool schemas to either arm. A timeout kills the session and is
    recorded rather than raised.
    """
    command = [
        *settings.claude_command,
        "-p",
        prompt,
        "--output-format",
        "stream-json",
        "--verbose",
        "--permission-mode",
        "auto",
        "--permission-prompts",
        "none",
        "--no-session-persistence",
        "--strict-mcp-config",
        "--max-budget-usd",
        str(settings.max_budget_usd),
    ]
    if settings.model is not None:
        command += ["--model", settings.model]
    if settings.effort is not None:
        command += ["--effort", settings.effort]

    exit_code: int | None = None
    timed_out = False
    with (
        transcript.open("wb") as stdout,
        transcript.with_suffix(".stderr").open("wb") as stderr,
    ):
        try:
            completed = subprocess.run(
                command,
                cwd=work_dir,
                env=session_environment(arm),
                stdin=subprocess.DEVNULL,
                stdout=stdout,
                stderr=stderr,
                timeout=settings.timeout_seconds,
                check=False,
            )
            exit_code = completed.returncode
        except subprocess.TimeoutExpired:
            timed_out = True

    metrics = parse_transcript(transcript.read_text(errors="replace"))
    metrics.exit_code = exit_code
    metrics.timed_out = timed_out
    return metrics


# Variables through which a parent Claude Code session reaches the processes
# it starts. Removing them lets the benchmark run from inside a session
# without its children attaching to that session.
PARENT_SESSION_VARIABLES = (
    "CLAUDECODE",
    "CLAUDE_PID",
    "CLAUDE_CODE_SESSION_ID",
    "CLAUDE_CODE_CHILD_SESSION",
    "CLAUDE_CODE_SESSION_ATTENDED",
    "CLAUDE_CODE_ENTRYPOINT",
    "CLAUDE_CODE_EXECPATH",
    "CLAUDE_CODE_MESSAGING_SOCKET",
    "CLAUDE_CODE_MESSAGING_TOKEN",
)


def session_environment(arm: Arm) -> dict[str, str]:
    environment = {
        name: value
        for name, value in os.environ.items()
        if name not in PARENT_SESSION_VARIABLES
    }
    environment["CLAUDE_HASHLINE"] = "1" if arm == Arm.HASHLINE else "0"
    return environment


def parse_transcript(text: str) -> SessionMetrics:
    """Read metrics from stream-json lines, skipping lines that are not JSON
    objects, so a truncated transcript still yields what it recorded."""
    metrics = SessionMetrics()
    tool_calls: Counter[str] = Counter()
    for line in text.splitlines():
        event = json_object(line)
        if event is None:
            continue

        match event.get("type"):
            case "system" if event.get("subtype") == "init":
                tools = event.get("tools")
                if isinstance(tools, list):
                    metrics.hashline_loaded = any(
                        isinstance(tool, str) and tool.startswith(HASHLINE_TOOL_PREFIX)
                        for tool in tools
                    )
            case "assistant":
                for block in content_blocks(event):
                    name = block.get("name")
                    if block.get("type") == "tool_use" and isinstance(name, str):
                        tool_calls[name] += 1
            case "user":
                for block in content_blocks(event):
                    if block.get("type") == "tool_result" and block.get("is_error") is True:
                        metrics.tool_errors += 1
            case "result":
                read_result_event(metrics, event)
            case _:
                pass

    metrics.tool_calls = dict(sorted(tool_calls.items()))
    return metrics


def read_result_event(metrics: SessionMetrics, event: dict[str, object]) -> None:
    metrics.result_subtype = optional_str(event.get("subtype"))
    metrics.is_error = optional_bool(event.get("is_error"))
    metrics.num_turns = optional_int(event.get("num_turns"))
    metrics.duration_ms = optional_int(event.get("duration_ms"))
    metrics.cost_usd = optional_float(event.get("total_cost_usd"))
    metrics.final_text = optional_str(event.get("result"))

    usage = event.get("usage")
    if isinstance(usage, dict):
        metrics.input_tokens = optional_int(usage.get("input_tokens"))
        metrics.output_tokens = optional_int(usage.get("output_tokens"))
        metrics.cache_read_tokens = optional_int(usage.get("cache_read_input_tokens"))
        metrics.cache_creation_tokens = optional_int(
            usage.get("cache_creation_input_tokens")
        )


def json_object(line: str) -> dict[str, object] | None:
    try:
        value: object = json.loads(line)
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def content_blocks(event: dict[str, object]) -> list[dict[str, object]]:
    message = event.get("message")
    if not isinstance(message, dict):
        return []
    content = message.get("content")
    if not isinstance(content, list):
        return []
    return [block for block in content if isinstance(block, dict)]


def metrics_from_json(fields: dict[str, object]) -> SessionMetrics:
    """Rebuild metrics saved with `dataclasses.asdict`; fields of the wrong
    type read as unknown."""
    tool_errors = optional_int(fields.get("tool_errors"))
    return SessionMetrics(
        exit_code=optional_int(fields.get("exit_code")),
        timed_out=fields.get("timed_out") is True,
        result_subtype=optional_str(fields.get("result_subtype")),
        is_error=optional_bool(fields.get("is_error")),
        num_turns=optional_int(fields.get("num_turns")),
        duration_ms=optional_int(fields.get("duration_ms")),
        cost_usd=optional_float(fields.get("cost_usd")),
        input_tokens=optional_int(fields.get("input_tokens")),
        output_tokens=optional_int(fields.get("output_tokens")),
        cache_read_tokens=optional_int(fields.get("cache_read_tokens")),
        cache_creation_tokens=optional_int(fields.get("cache_creation_tokens")),
        tool_calls=tool_call_counts(fields.get("tool_calls")),
        tool_errors=0 if tool_errors is None else tool_errors,
        hashline_loaded=optional_bool(fields.get("hashline_loaded")),
        final_text=optional_str(fields.get("final_text")),
    )


def tool_call_counts(value: object) -> dict[str, int]:
    if not isinstance(value, dict):
        return {}
    counts: dict[str, int] = {}
    for name, count in cast(dict[object, object], value).items():
        known = optional_int(count)
        if isinstance(name, str) and known is not None:
            counts[name] = known
    return counts


def optional_int(value: object) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def optional_float(value: object) -> float | None:
    if isinstance(value, bool) or not isinstance(value, int | float):
        return None
    return float(value)


def optional_bool(value: object) -> bool | None:
    return value if isinstance(value, bool) else None


def optional_str(value: object) -> str | None:
    return value if isinstance(value, str) else None
