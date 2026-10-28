"""The ``jj-push-dry-run`` check: refuse a `jj git push` whose dry run is unsafe.

The check reruns the agent's push with ``--dry-run`` through the real jj, in
the invocation's environment, and reads jj's report of what the push would
change. It passes only when every bookmark change adds a bookmark or moves one
forward and no more bookmarks change than the command names targets (each
``-b``, ``-c``, or ``--named`` argument counts once, as given). Anything else
refuses: a sideways or backward move, a deletion, an excess, a failed dry run,
a report without its header, or any line the check does not recognize, so a
change in jj's output format fails toward asking the user.

Recognized report lines, observed with jj 0.46 (jj writes them to stderr)::

    Creating bookmark <name> for revision <change-id>
    Bookmark <name>@<remote> already matches <name>
    Changes to push to <remote>:
      bookmark: <name> [<action>]
    Dry-run requested, not pushing.
    Nothing changed.
    Hint: ...

with actions ``add to <id>``, ``move forward from <id> to <id>``,
``move sideways from <id> to <id>``, ``move backward from <id> to <id>``, and
``delete from <id>``.
"""

from __future__ import annotations

import re
import shlex
import subprocess
from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .checks import CheckRequest
    from .invocation import ParsedInvocation

DRY_RUN_OPTION = "--dry-run"

# Global options that would hide or decorate the report the check reads:
# `--quiet` suppresses it entirely, `--debug` adds log lines, and `--color`
# adds escape codes. The dry run drops them and forces `--color=never`.
_REPORT_ALTERING_GLOBAL_OPTIONS = frozenset({"--quiet", "--debug", "--color"})
_NO_COLOR_OPTION = "--color=never"


def jj_push_dry_run_refusal(request: CheckRequest) -> str | None:
    """Dry-run the push in REQUEST and return why it is refused, or ``None``.

    An invocation that already has ``--dry-run`` changes nothing, so it passes
    without a second run. The returned reason is a clause without a final
    period.
    """
    invocation = request.invocation
    if any(option.spelling == DRY_RUN_OPTION for option in invocation.options):
        return None

    argv = dry_run_argv(invocation)
    completed = subprocess.run(
        [*request.real_command, *argv],
        env=dict(request.environment),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )

    command = shlex.join(["jj", *argv])
    if completed.returncode != 0:
        return _dry_run_failure_reason(command, completed.returncode, completed.stdout)
    target_count = len(invocation.occurrences_of(request.rule.target_options))
    return dry_run_report_problem(read_dry_run_report(completed.stdout), target_count, command)


def dry_run_argv(invocation: ParsedInvocation) -> list[str]:
    """Return the invocation's argv as a colorless, unquiet dry run.

    Drops ``--quiet``, ``--debug``, and ``--color`` wherever they appear as
    global options, then adds ``--dry-run`` and ``--color=never`` before any
    ``--``.
    """
    dropped_indexes = {
        index
        for option in invocation.options
        if option.is_global
        and option.declaration is not None
        and not _REPORT_ALTERING_GLOBAL_OPTIONS.isdisjoint(option.declaration.names)
        for index in range(option.start, option.end)
    }
    options_part = [
        token for index, token in enumerate(invocation.argv[: invocation.operands_start]) if index not in dropped_indexes
    ]
    return [
        *options_part,
        DRY_RUN_OPTION,
        _NO_COLOR_OPTION,
        *invocation.argv[invocation.operands_start :],
    ]


def _dry_run_failure_reason(command: str, exit_status: int, output: str) -> str:
    output_lines = [line for line in output.splitlines() if line.strip() != ""]
    detail = f": {output_lines[-1]}" if len(output_lines) > 0 else ""
    return (
        f"its dry run `{command}` failed with exit status {exit_status}{detail}"
        + "; this is not a policy violation, but without a dry run the policy cannot tell"
        + " what the push would change (if the remote is unreachable, retry when it is)"
    )


class BookmarkAction(Enum):
    """What a push would do to one remote bookmark."""

    ADD = "add"
    MOVE_FORWARD = "move forward"
    MOVE_SIDEWAYS = "move sideways"
    MOVE_BACKWARD = "move backward"
    DELETE = "delete"


SAFE_BOOKMARK_ACTIONS = frozenset({BookmarkAction.ADD, BookmarkAction.MOVE_FORWARD})
"""Actions that never discard a commit from the remote."""


@dataclass(frozen=True)
class BookmarkChange:
    """One ``bookmark: <name> [<action>]`` line of a dry-run report."""

    name: str
    action: BookmarkAction
    description: str
    """jj's bracketed action text, such as ``move backward from a to b``."""


@dataclass(frozen=True)
class DryRunReport:
    """What a `jj git push --dry-run` printed, read line by line."""

    bookmark_changes: tuple[BookmarkChange, ...]
    has_changes_header: bool
    """Whether a ``Changes to push to <remote>:`` line appeared."""
    has_nothing_changed: bool
    """Whether a ``Nothing changed.`` line appeared."""
    unrecognized_lines: tuple[str, ...]


_IGNORED_LINE_PATTERNS = (
    re.compile(r"Creating bookmark \S+ for revision \S+"),
    re.compile(r"Bookmark \S+ already matches \S+"),
    re.compile(r"Dry-run requested, not pushing\."),
    re.compile(r"Hint: .*"),
    re.compile(r""),
)
_CHANGES_HEADER = re.compile(r"Changes to push to \S+:")
_NOTHING_CHANGED = "Nothing changed."
_BOOKMARK_CHANGE = re.compile(r"  bookmark: (?P<name>\S+) \[(?P<description>[^\[\]]+)\]")
_ACTION_DESCRIPTIONS = (
    (BookmarkAction.ADD, re.compile(r"add to \w+")),
    (BookmarkAction.MOVE_FORWARD, re.compile(r"move forward from \w+ to \w+")),
    (BookmarkAction.MOVE_SIDEWAYS, re.compile(r"move sideways from \w+ to \w+")),
    (BookmarkAction.MOVE_BACKWARD, re.compile(r"move backward from \w+ to \w+")),
    (BookmarkAction.DELETE, re.compile(r"delete from \w+")),
)


def read_dry_run_report(output: str) -> DryRunReport:
    """Read jj's dry-run OUTPUT (stdout and stderr together) into a report."""
    changes: list[BookmarkChange] = []
    has_changes_header = False
    has_nothing_changed = False
    unrecognized: list[str] = []
    for line in output.splitlines():
        if any(pattern.fullmatch(line) is not None for pattern in _IGNORED_LINE_PATTERNS):
            continue
        if _CHANGES_HEADER.fullmatch(line) is not None:
            has_changes_header = True
            continue
        if line == _NOTHING_CHANGED:
            has_nothing_changed = True
            continue

        change = _read_bookmark_change(line)
        if change is None:
            unrecognized.append(line)
        else:
            changes.append(change)

    return DryRunReport(
        bookmark_changes=tuple(changes),
        has_changes_header=has_changes_header,
        has_nothing_changed=has_nothing_changed,
        unrecognized_lines=tuple(unrecognized),
    )


def _read_bookmark_change(line: str) -> BookmarkChange | None:
    match = _BOOKMARK_CHANGE.fullmatch(line)
    if match is None:
        return None
    description = match["description"]
    for action, pattern in _ACTION_DESCRIPTIONS:
        if pattern.fullmatch(description) is not None:
            return BookmarkChange(match["name"], action, description)
    return None


def dry_run_report_problem(report: DryRunReport, target_count: int, command: str) -> str | None:
    """Describe why REPORT makes the push unsafe, or return ``None``.

    TARGET_COUNT is the number of targets the command names; COMMAND is the
    dry-run command line, quoted in reasons.
    """
    problems: list[str] = []
    if len(report.unrecognized_lines) > 0:
        quoted = ", ".join(f"`{line}`" for line in report.unrecognized_lines)
        problems.append(f"its dry run `{command}` printed lines the policy does not recognize: {quoted}")
    if not report.has_changes_header and not report.has_nothing_changed:
        problems.append(
            f"its dry run `{command}` reported neither `Changes to push to <remote>:` nor `Nothing changed.`,"
            + " so the policy cannot tell what the push would change"
        )

    unsafe = [change for change in report.bookmark_changes if change.action not in SAFE_BOOKMARK_ACTIONS]
    if len(unsafe) > 0:
        described = ", ".join(f"`{change.name}` ({change.description})" for change in unsafe)
        problems.append(
            f"its dry run shows bookmark changes that are not additions or forward moves: {described};"
            + " moving a remote bookmark sideways or backward, or deleting it, is a force push"
        )

    change_count = len(report.bookmark_changes)
    if change_count > target_count:
        problems.append(
            f"its dry run changes {change_count} bookmarks but the command names only {target_count}"
            + f" {_plural('target', target_count)}; name each bookmark to push with its own `-b`"
        )

    return None if len(problems) == 0 else "; ".join(problems)


def _plural(noun: str, count: int) -> str:
    return noun if count == 1 else f"{noun}s"
