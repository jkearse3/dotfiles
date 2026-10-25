"""Find and jump to Herdr agents and workspaces.

``rows`` lists the open agents and workspaces as picker rows: agents first,
most in need of attention first, then workspaces in sidebar order. Each row is
``TARGET<TAB>DISPLAY``, where TARGET is ``agent:<pane_id>`` or
``workspace:<workspace_id>`` and DISPLAY is the text a picker shows and
searches.

``preview TARGET`` prints what a picker shows beside the selected row.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import unicodedata
from collections import Counter
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Literal, cast

PROGRAM = "herdr-find"

# Agent statuses in the order agents are listed, most in need of the user
# first. A status Herdr reports outside this list ranks with "unknown".
AGENT_STATUS_ORDER = ("blocked", "done", "idle", "working", "unknown")

AGENT_TARGET_PREFIX = "agent:"
WORKSPACE_TARGET_PREFIX = "workspace:"

RowKind = Literal["agents", "workspaces"]


class FindError(Exception):
    """A concise, user-facing failure."""


@dataclass(frozen=True)
class Caller:
    """Where the picker was opened from; its own rows sort last in their groups.

    An empty ID means that part of the location is unknown.
    """

    workspace_id: str = ""
    pane_id: str = ""


def rows(*, only: RowKind | None, caller: Caller) -> list[str]:
    """Return the picker rows for Herdr's open agents and workspaces.

    Agents sort by status in AGENT_STATUS_ORDER, then most recent status
    change first; workspaces by sidebar number. The CALLER's agent and
    workspace sort last in their groups. ONLY limits the rows to one group.
    Raises FindError when a herdr call fails.
    """
    agents = _agents()
    workspaces = _workspaces()

    lines: list[str] = []
    if only != "workspaces":
        labels = {workspace.workspace_id: workspace.label for workspace in workspaces}
        lines += _agent_rows(agents, labels, caller)
    if only != "agents":
        lines += _workspace_rows(workspaces, agents, caller)
    return lines


@dataclass(frozen=True)
class Agent:
    """An agent pane from ``herdr agent list``, with display fields sanitized.

    IDs are kept as Herdr reports them, for joining and comparison.
    STATE_CHANGE_SEQ is Herdr's counter of when the status last changed,
    higher meaning more recent, or None when Herdr did not report it.
    """

    pane_id: str
    workspace_id: str
    agent: str
    status: str
    title: str
    directory: str
    state_change_seq: int | None


def _agents() -> list[Agent]:
    return [
        Agent(
            pane_id=_string(agent.get("pane_id")),
            workspace_id=_string(agent.get("workspace_id")),
            agent=sanitize(_string(agent.get("agent"))),
            status=_agent_status(sanitize(_string(agent.get("agent_status")))),
            title=sanitize(_string(agent.get("terminal_title_stripped"))),
            directory=sanitize(_home_relative(_string(agent.get("cwd")))),
            state_change_seq=_integer(agent.get("state_change_seq")),
        )
        for agent in _herdr_list("agents", "agent", "list")
    ]


def _agent_rows(agents: Sequence[Agent], labels: dict[str, str], caller: Caller) -> list[str]:
    def order(agent: Agent) -> tuple[bool, int, int]:
        seq = agent.state_change_seq if agent.state_change_seq is not None else -1
        return (agent.pane_id == caller.pane_id, _status_rank(agent.status), -seq)

    listed = sorted((agent for agent in agents if agent.pane_id != ""), key=order)
    cell_rows = [
        [
            _status_cell(agent.status),
            (agent.agent, ""),
            (agent.title, ""),
            (labels.get(agent.workspace_id, ""), ""),
            (agent.directory, _DIM),
        ]
        for agent in listed
    ]
    targets = [AGENT_TARGET_PREFIX + sanitize(agent.pane_id) for agent in listed]
    return _table(targets, cell_rows)


@dataclass(frozen=True)
class Workspace:
    """A workspace from ``herdr workspace list``, with display fields sanitized.

    IDs are kept as Herdr reports them, for joining and comparison.
    CHECKOUT_PATH is empty when the workspace is not a Git worktree. NUMBER is
    the sidebar position, or None when Herdr did not report it.
    """

    workspace_id: str
    label: str
    number: int | None
    checkout_path: str
    active_tab_id: str


def _workspaces() -> list[Workspace]:
    return [
        Workspace(
            workspace_id=_string(workspace.get("workspace_id")),
            label=sanitize(_string(workspace.get("label"))),
            number=_integer(workspace.get("number")),
            checkout_path=_string(_object(workspace.get("worktree")).get("checkout_path")),
            active_tab_id=_string(workspace.get("active_tab_id")),
        )
        for workspace in _herdr_list("workspaces", "workspace", "list")
    ]


def _workspace_rows(workspaces: Sequence[Workspace], agents: Sequence[Agent], caller: Caller) -> list[str]:
    def order(workspace: Workspace) -> tuple[bool, bool, int]:
        number = workspace.number if workspace.number is not None else 0
        return (workspace.workspace_id == caller.workspace_id, workspace.number is None, number)

    listed = sorted((workspace for workspace in workspaces if workspace.workspace_id != ""), key=order)
    directories = _workspace_directories(listed)
    cell_rows = [
        [
            (workspace.label, _BOLD),
            (directories.get(workspace.workspace_id, ""), _DIM),
            (_agent_summary(workspace.workspace_id, agents), ""),
        ]
        for workspace in listed
    ]
    targets = [WORKSPACE_TARGET_PREFIX + sanitize(workspace.workspace_id) for workspace in listed]
    return _table(targets, cell_rows)


def _workspace_directories(workspaces: Sequence[Workspace]) -> dict[str, str]:
    """Return each workspace's display directory, keyed by workspace ID.

    A workspace that is not a Git worktree shows the directory of one of its
    panes: in its active tab, the focused pane if any, else the first; else its
    first pane anywhere. Panes are listed only when some workspace needs them.
    """
    directories = {
        workspace.workspace_id: workspace.checkout_path for workspace in workspaces if workspace.checkout_path != ""
    }
    if len(directories) < len(workspaces):
        panes = _herdr_list("panes", "pane", "list")
        for workspace in workspaces:
            if workspace.workspace_id not in directories:
                directories[workspace.workspace_id] = _pane_directory(workspace, panes)
    return {workspace_id: sanitize(_home_relative(directory)) for workspace_id, directory in directories.items()}


def _pane_directory(workspace: Workspace, panes: Sequence[dict[str, object]]) -> str:
    owned = [pane for pane in panes if pane.get("workspace_id") == workspace.workspace_id]
    in_active_tab = [pane for pane in owned if pane.get("tab_id") == workspace.active_tab_id]
    focused = [pane for pane in in_active_tab if pane.get("focused") is True]
    for candidates in (focused, in_active_tab, owned):
        if len(candidates) > 0:
            return _string(candidates[0].get("cwd"))
    return ""


def _agent_summary(workspace_id: str, agents: Sequence[Agent]) -> str:
    """Return a count of WORKSPACE_ID's agents by status, like "1 blocked, 2 idle"."""
    counts = Counter(agent.status for agent in agents if agent.workspace_id == workspace_id)
    if len(counts) == 0:
        return "no agents"
    statuses = sorted(counts, key=lambda status: (_status_rank(status), status))
    return ", ".join(f"{counts[status]} {status}" for status in statuses)


def _agent_status(reported: str) -> str:
    return reported if reported != "" else "unknown"


def _status_rank(status: str) -> int:
    known = status if status in AGENT_STATUS_ORDER else "unknown"
    return AGENT_STATUS_ORDER.index(known)


TargetKind = Literal["agent", "workspace"]


@dataclass(frozen=True)
class Target:
    """A row's TARGET field: the agent pane or workspace the row stands for."""

    kind: TargetKind
    id: str


def parse_target(text: str) -> Target:
    """Return the target TEXT names, ``agent:<pane_id>`` or ``workspace:<workspace_id>``.

    Raises FindError when TEXT has neither prefix or names no ID.
    """
    if text.startswith(AGENT_TARGET_PREFIX) and text != AGENT_TARGET_PREFIX:
        return Target(kind="agent", id=text.removeprefix(AGENT_TARGET_PREFIX))
    if text.startswith(WORKSPACE_TARGET_PREFIX) and text != WORKSPACE_TARGET_PREFIX:
        return Target(kind="workspace", id=text.removeprefix(WORKSPACE_TARGET_PREFIX))
    raise FindError(f"malformed target {text!r}: expected agent:PANE_ID or workspace:WORKSPACE_ID")


# Lines of recent terminal output an agent's preview shows.
AGENT_PREVIEW_LINES = 40


def preview(target: Target) -> str:
    """Return the preview text for TARGET's row.

    An agent's preview is its recent terminal output as Herdr reports it. A
    workspace's preview lists its tabs, each followed by its panes' agent (or
    "shell" when none runs), status, and title. Raises FindError when a herdr
    call fails.
    """
    if target.kind == "agent":
        line_count = str(AGENT_PREVIEW_LINES)
        return _herdr_text("agent", "read", target.id, "--source", "recent-unwrapped", "--lines", line_count)
    return "".join(f"{line}\n" for line in _workspace_preview(target.id))


def _workspace_preview(workspace_id: str) -> list[str]:
    tabs = _herdr_list("tabs", "tab", "list", "--workspace", workspace_id)
    panes = _herdr_list("panes", "pane", "list", "--workspace", workspace_id)

    pane_rows = [
        (
            _string(pane.get("tab_id")),
            [
                (_text_or(sanitize(_string(pane.get("agent"))), "shell"), ""),
                _status_cell(_agent_status(sanitize(_string(pane.get("agent_status"))))),
                (sanitize(_string(pane.get("terminal_title_stripped"))), ""),
            ],
        )
        for pane in panes
    ]
    # Align agent and status across all of the workspace's panes; the title is last.
    widths = [max((len(cells[index][0]) for _tab_id, cells in pane_rows), default=0) for index in range(2)] + [0]

    lines: list[str] = []
    for tab in tabs:
        tab_id = _string(tab.get("tab_id"))
        lines.append(_coloured(_text_or(sanitize(_string(tab.get("label"))), sanitize(tab_id)), _BOLD))
        for pane_tab_id, cells in pane_rows:
            if pane_tab_id == tab_id:
                padded = [_coloured(text.ljust(width), colour) for (text, colour), width in zip(cells, widths, strict=True)]
                lines.append(f"  {_COLUMN_SEPARATOR.join(padded).rstrip()}")
    return lines


def _text_or(text: str, fallback: str) -> str:
    return text if text != "" else fallback


# A display cell: its sanitized text and the SGR escape that colours it, or ""
# for the terminal's default.
_Cell = tuple[str, str]

_BOLD = "\x1b[1m"
_DIM = "\x1b[2m"
_RESET = "\x1b[0m"
_STATUS_COLOURS = {
    "blocked": "\x1b[31m",
    "done": "\x1b[32m",
    "idle": "\x1b[33m",
    "working": "\x1b[34m",
}
_COLUMN_SEPARATOR = "  "


def _status_cell(status: str) -> _Cell:
    return (status, _STATUS_COLOURS.get(status, _DIM))


def _table(targets: Sequence[str], cell_rows: Sequence[Sequence[_Cell]]) -> list[str]:
    """Return one row per target, its cells padded into aligned columns.

    Padding is computed from the uncoloured text, so colours do not skew
    alignment. The last cell is not padded, and empty cells at the end of a row
    are dropped.
    """
    column_count = max((len(row) for row in cell_rows), default=0)
    widths = [max(len(row[index][0]) for row in cell_rows) for index in range(column_count)]
    if len(widths) > 0:
        widths[-1] = 0
    lines: list[str] = []
    for target, row in zip(targets, cell_rows, strict=True):
        cells = [_coloured(text.ljust(width), colour) for (text, colour), width in zip(row, widths, strict=True)]
        lines.append(f"{target}\t{_COLUMN_SEPARATOR.join(cells).rstrip()}")
    return lines


def _coloured(text: str, colour: str) -> str:
    return f"{colour}{text}{_RESET}" if colour != "" and text.strip() != "" else text


# CSI, OSC, and two-character escape sequences, as terminals emit them in titles.
_ANSI_ESCAPE = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\)?|[@-Z\\-_])")


def sanitize(text: str) -> str:
    """Return TEXT as one line safe to place in a row.

    Removes ANSI escape sequences, turns every other control character into a
    space, and collapses runs of whitespace, so TEXT cannot add a tab-separated
    field, a line, or terminal styling to a row.
    """
    without_escapes = _ANSI_ESCAPE.sub("", text)
    spaced = "".join(" " if unicodedata.category(character) == "Cc" else character for character in without_escapes)
    return " ".join(spaced.split())


def _home_relative(path: str) -> str:
    home = str(Path.home())
    if path == home:
        return "~"
    if path.startswith(home.rstrip("/") + "/"):
        return "~" + path[len(home.rstrip("/")) :]
    return path


def _herdr_list(key: str, *arguments: str) -> list[dict[str, object]]:
    """Return the records under result.KEY of herdr's JSON reply to ARGUMENTS."""
    records = _object(_herdr_json(*arguments).get("result")).get(key)
    if not isinstance(records, list):
        raise FindError(f"{shlex.join(['herdr', *arguments])} returned no {key}")
    return [_object(record) for record in cast(list[object], records)]


def _herdr_json(*arguments: str) -> dict[str, object]:
    command = [_herdr(), *arguments]
    stdout = _herdr_text(*arguments)
    try:
        return _object(cast(object, json.loads(stdout)))
    except json.JSONDecodeError as error:
        raise FindError(f"{shlex.join(command)} returned malformed JSON") from error


def _herdr_text(*arguments: str) -> str:
    """Return herdr's stdout for ARGUMENTS; raise FindError when it fails."""
    command = [_herdr(), *arguments]
    result = _run(command)
    if result.returncode != 0:
        detail = _herdr_failure_detail(result)
        raise FindError(f"{shlex.join(command)} failed" + (f": {detail}" if detail != "" else ""))
    return result.stdout


def _herdr_failure_detail(result: subprocess.CompletedProcess[str]) -> str:
    """Return why a herdr call failed, from its stderr or else its stdout.

    Herdr reports a failed request as a JSON error reply; its message is used
    when present, otherwise the output as written.
    """
    output = _text_or(result.stderr.strip(), result.stdout.strip())
    try:
        reply = _object(cast(object, json.loads(output)))
    except json.JSONDecodeError:
        return output
    message = sanitize(_string(_object(reply.get("error")).get("message")))
    return message if message != "" else output


def _herdr() -> str:
    herdr = os.environ.get("HERDR_BIN_PATH", "")
    return herdr if herdr != "" else "herdr"


def _run(command: Sequence[str]) -> subprocess.CompletedProcess[str]:
    """Run COMMAND capturing stdout and stderr."""
    try:
        return subprocess.run(command, check=False, capture_output=True, text=True)
    except OSError as error:
        raise FindError(f"could not run {command[0]}: {error}") from error


def _object(value: object) -> dict[str, object]:
    return cast(dict[str, object], value) if isinstance(value, dict) else {}


def _string(value: object) -> str:
    return value if isinstance(value, str) else ""


def _integer(value: object) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def _command_rows(arguments: argparse.Namespace) -> int:
    caller = Caller(
        workspace_id=cast(str, arguments.caller_workspace),
        pane_id=cast(str, arguments.caller_pane),
    )
    for line in rows(only=cast(RowKind | None, arguments.only), caller=caller):
        print(line)
    return 0


def _command_preview(arguments: argparse.Namespace) -> int:
    _ = sys.stdout.write(preview(parse_target(cast(str, arguments.target))))
    return 0


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog=PROGRAM, description="Find and jump to Herdr agents and workspaces.")
    commands = parser.add_subparsers(dest="command", required=True, metavar="COMMAND")

    rows_parser = commands.add_parser(
        "rows",
        help="print the picker rows for open agents and workspaces",
        description=(
            "Print one TARGET<TAB>DISPLAY row per open agent, most in need of "
            "attention first, then per workspace in sidebar order. TARGET is "
            "agent:PANE_ID or workspace:WORKSPACE_ID; DISPLAY may contain ANSI colour."
        ),
    )
    _ = rows_parser.add_argument("--only", choices=("agents", "workspaces"), help="print only one group of rows")
    _ = rows_parser.add_argument(
        "--caller-workspace", metavar="ID", default="", help="workspace to list last among workspaces"
    )
    _ = rows_parser.add_argument("--caller-pane", metavar="ID", default="", help="agent pane to list last among agents")
    rows_parser.set_defaults(handler=_command_rows)

    preview_parser = commands.add_parser(
        "preview",
        help="print the preview for one picker row",
        description=(
            "Print an agent's recent terminal output, or a workspace's tabs and "
            "their panes' agents, statuses, and titles. A failure is reported on "
            "stderr with a non-zero exit status."
        ),
    )
    _ = preview_parser.add_argument("target", metavar="TARGET", help="agent:PANE_ID or workspace:WORKSPACE_ID")
    preview_parser.set_defaults(handler=_command_preview)
    return parser


def main(arguments: Sequence[str] | None = None) -> int:
    """Run the CLI; return its exit status, 1 after reporting a failure."""
    parsed = _parser().parse_args(arguments)
    handler = cast(Callable[[argparse.Namespace], int], parsed.handler)
    try:
        return handler(parsed)
    except KeyboardInterrupt:
        return 1
    except FindError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
