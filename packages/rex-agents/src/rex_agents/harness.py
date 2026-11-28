"""Build the commands and task text that launch or resume a helper agent.

`modules/home/terminal/agent-terminals.md` states the same stem and
result-path rules, harness commands, resume procedure, and instructions for
agents that follow it by hand under herdr-core. Change both together.
"""

from __future__ import annotations

import re
from pathlib import Path

HARNESSES = ("claude", "pi", "opencode")

# `<name>` is 1 to 21 characters of a-z, 0-9, and `-`; the stem appends the
# unix time, so it fits the harnesses' session-name limits.
NAME_PATTERN = re.compile(r"[a-z0-9-]{1,21}")


def stem_for(name: str, unix_time: int) -> str:
    """Return the stem that names a helper's tab and harness session."""
    return f"{name}-{unix_time}"


def result_path(tmpdir: Path, stem: str, unix_time: int) -> Path:
    """Return one launch's result path in the caller's agent-reports directory."""
    return tmpdir / "agent-reports" / f"{stem}-{unix_time}.md"


def start_command(harness: str, stem: str, task: str) -> list[str]:
    """Return the argv that starts HARNESS on TASK in a session named STEM."""
    if harness == "claude":
        return ["claude", "--name", stem, task]
    if harness == "pi":
        return ["pi", "--session-id", stem, "--name", stem, task]
    if harness == "opencode":
        return ["opencode", "--session", f"ses_{stem}", "--prompt", task]
    raise ValueError(f"unknown harness {harness}")


def resume_command(harness: str, stem: str, task: str) -> list[str]:
    """Return the argv that continues STEM's session with TASK."""
    if harness == "claude":
        return ["claude", "--resume", stem, task]
    if harness == "pi":
        return ["pi", "--session-id", stem, task]
    if harness == "opencode":
        return ["opencode", "--session", f"ses_{stem}", "--prompt", task]
    raise ValueError(f"unknown harness {harness}")


def start_task(task: str, result: Path) -> str:
    """Return TASK followed by the instructions every helper gets."""
    return f"{task.rstrip()}\n\n{_instructions(result)}"


def resume_task(task: str, result: Path, earlier_result: Path) -> str:
    """Return a follow-up TASK with the instructions for a resumed helper."""
    return (
        f"{task.rstrip()}\n\n{_instructions(result)} Do not write to the earlier "
        f"result file, {earlier_result}. If you do not recognize your earlier "
        f"task, write `no earlier context` to {result} and stop."
    )


def _instructions(result: Path) -> str:
    return (
        "Another agent started you. When you finish, write your result, or what "
        f"blocks you, to {result}, then end your turn. Report only by writing "
        "that file. Start no agents unless the user authorizes it in your own "
        "terminal."
    )
