"""Find and jump to Herdr agents and workspaces.

``rows`` lists the open agents and workspaces as picker rows: agents first,
most in need of attention first, then workspaces in sidebar order. Each row is
``TARGET<TAB>DISPLAY``, where TARGET is ``agent:<pane_id>`` or
``workspace:<workspace_id>`` and DISPLAY is the text a picker shows and
searches. With ``--picker-header``, the rows follow the picker's header line,
and a failure to list them is printed in that line's place, for a picker that
shows only its input.

``preview TARGET`` prints what a picker shows beside the selected row.

``pick`` is the picker itself: it shows the rows in fzf and focuses the chosen
agent pane or workspace. ``open-popup ENTRYPOINT`` is the Herdr plugin action
that opens the picker's popup pane.

``serve --host app`` is the desktop app's long-lived picker: one fzf process
that popups show again and again, its keys calling back into this CLI
(``accept-action``, ``dismiss``, ``request-reload-action``) instead of ending
fzf. A popup's ``show`` loads fresh rows into it over its socket, and
``reset`` clears it when that popup closes.

``--host`` names which Herdr ``rows``, ``preview``, ``pick`` and
``reload-action`` drive: ``tui``, the Herdr terminal UI through its ``herdr``
CLI, or ``app``, the Herdr desktop app through ``herdr-app`` and herdr-core's
``hc``. Under ``app``, a workspace is an app space and an agent pane is a
core terminal address, so TARGET is ``agent:<address>`` or
``workspace:<space_id>``.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import shlex
import socket
import subprocess
import sys
import tempfile
import time
import unicodedata
from collections import Counter
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Literal, cast, override

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


# Which Herdr a command drives: the terminal UI or the desktop app.
Host = Literal["tui", "app"]
HOSTS: tuple[Host, ...] = ("tui", "app")


def default_host() -> Host:
    """Return the Herdr this process runs in, for when --host is omitted.

    A terminal of the desktop app's core has $HC_TERMINAL_ID; the TUI sets
    HERDR_ENV=1 in its panes and plugin popups, including a TUI running inside
    an app terminal. Anything else, such as a plain shell, counts as the TUI.
    """
    in_core_terminal = os.environ.get("HC_TERMINAL_ID", "") != ""
    return "app" if in_core_terminal and os.environ.get("HERDR_ENV") != "1" else "tui"


def rows(*, only: RowKind | None, caller: Caller, host: Host) -> list[str]:
    """Return the picker rows for HOST's open agents and workspaces.

    Agents sort by status in AGENT_STATUS_ORDER, then, in the TUI, most recent
    status change first; workspaces by sidebar position. The CALLER's agent
    and workspace sort last in their groups. ONLY limits the rows to one group.
    Raises FindError when a herdr, herdr-app, or hc call fails.
    """
    if host == "app":
        return _app_rows(only=only, caller=caller)

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

    In the app, an agent is a status-reporting core terminal: PANE_ID is its
    address and WORKSPACE_ID its space's ID. IDs are kept as Herdr reports
    them, for joining and comparison.
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


def preview(target: Target, host: Host) -> str:
    """Return the preview text for TARGET's row in HOST.

    An agent's preview is its recent terminal output as Herdr reports it. A
    workspace's preview lists its tabs, each followed by its panes' agent (or
    "shell" when none runs), status, and title; in the app it starts with the
    space's name and folder. Raises FindError when a herdr, herdr-app, or hc
    call fails, or when the app has no such space.
    """
    if host == "app":
        return _app_preview(target)

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


# fzf's exit statuses when the user closes it without choosing a row: no row
# matched the query, or the user pressed Esc or ctrl-c.
FZF_NO_MATCH = 1
FZF_INTERRUPTED = 130

# The picker's row filter, shown as its fzf prompt so key bindings can read the
# current filter back from $FZF_PROMPT. None shows every row.
FILTER_PROMPTS: dict[RowKind | None, str] = {
    None: "> ",
    "agents": "agents> ",
    "workspaces": "workspaces> ",
}

PICKER_KEY_HINTS = "ctrl-a agents  ctrl-w workspaces  ctrl-r refresh  ctrl-o preview  ctrl-u/ctrl-d scroll preview"


def picker_header_line() -> str:
    """Return the line the picker's input starts with: its key hints.

    fzf shows it above the rows (--header-lines=1), never filtered or
    selectable. Like a row it is TARGET<TAB>DISPLAY, with an empty TARGET, so
    fzf shows its DISPLAY.
    """
    return f"\t{PICKER_KEY_HINTS}"


def picker_error_line(message: str) -> str:
    """Return a header line, in picker_header_line's place, that reports MESSAGE.

    fzf drops a reload command's stderr and keeps the query, which could filter
    out any row, so a reload's failure is shown as the header line instead.
    """
    return f"\t{_coloured(f'error: {sanitize(message)}', _ERROR_COLOUR)}"


def pick(caller: Caller, host: Host) -> None:
    """Show HOST's picker rows in fzf and focus the agent pane or workspace chosen.

    CALLER's rows sort last, also after a reload, and reloads and previews
    keep driving HOST. Focus is left unchanged when the user closes fzf
    without choosing a row. Raises FindError when listing the rows, running
    fzf, or focusing the target fails, for example because the chosen agent
    has since closed.
    """
    listed = [picker_header_line(), *rows(only=None, caller=caller, host=host)]

    command = [_fzf(), *_pick_fzf_options(caller, host)]
    try:
        result = subprocess.run(
            command,
            input="".join(f"{line}\n" for line in listed),
            stdout=subprocess.PIPE,
            check=False,
            text=True,
        )
    except OSError as error:
        raise FindError(f"could not run {command[0]}: {error}") from error
    if result.returncode in (FZF_NO_MATCH, FZF_INTERRUPTED):
        return
    if result.returncode != 0:
        raise FindError(f"fzf exited with status {result.returncode}")

    chosen = result.stdout.split("\n", 1)[0]
    focus(parse_target(chosen.split("\t", 1)[0]), host)


def _pick_fzf_options(caller: Caller, host: Host) -> list[str]:
    """Return fzf's options for ``pick``: the shared display, with reload keys naming HOST and CALLER."""
    self_command = _self_command()

    def reload_binding(key: str, reload_key: ReloadKey) -> str:
        arguments = shlex.join(["reload-action", reload_key, *_host_options(host), *_caller_options(caller)])
        return f"{key}:transform:{self_command} {arguments}"

    return [
        *_fzf_display_options(host),
        *(f"--bind={reload_binding(key, reload_key)}" for key, reload_key in RELOAD_KEYS),
        *_PREVIEW_KEY_OPTIONS,
    ]


def _fzf_display_options(host: Host) -> list[str]:
    """Return fzf's options for showing rows: the display searched, the target kept for actions.

    The input's first line is the picker's header line. Key bindings and the
    preview call back into this CLI through /bin/sh, not the user's shell; the
    preview drives HOST. ctrl-j/ctrl-k keep fzf's default of moving the
    selection.
    """
    preview_arguments = shlex.join(["preview", *_host_options(host)])
    return [
        "--delimiter=\t",
        "--with-nth=2..",
        "--ansi",
        "--tiebreak=index",
        "--layout=reverse",
        "--with-shell=/bin/sh -c",
        f"--prompt={FILTER_PROMPTS[None]}",
        "--header-lines=1",
        f"--preview={_self_command()} {preview_arguments} {{1}}",
        "--preview-window=down,50%,wrap,follow",
    ]


# The picker keys that show, hide and scroll the preview.
_PREVIEW_KEY_OPTIONS = (
    "--bind=ctrl-o:toggle-preview",
    "--bind=ctrl-u:preview-half-page-up",
    "--bind=ctrl-d:preview-half-page-down",
)


# What a picker key asks of the rows: list them again with the current filter,
# or toggle a filter to one group.
ReloadKey = Literal["refresh", "agents", "workspaces"]

# The picker keys that reload its rows, and what each asks of them.
RELOAD_KEYS: tuple[tuple[str, ReloadKey], ...] = (
    ("ctrl-r", "refresh"),
    ("ctrl-a", "agents"),
    ("ctrl-w", "workspaces"),
)


def reload_action(key: ReloadKey, prompt: str, caller: Caller, host: Host) -> str:
    """Return the fzf action that reloads HOST's picker rows for KEY.

    PROMPT is the picker's current fzf prompt, which names its filter as in
    FILTER_PROMPTS; an unrecognised prompt counts as showing every row.
    "refresh" keeps the filter. "agents" or "workspaces" shows only that group,
    or every row again when that group is already the filter. CALLER's rows
    sort last.
    """
    current = next((only for only, shown in FILTER_PROMPTS.items() if shown == prompt), None)
    if key == "refresh":
        return f"reload:{_rows_command(current, caller, host)}"
    chosen: RowKind | None = None if current == key else key
    return f"change-prompt({FILTER_PROMPTS[chosen]})+reload:{_rows_command(chosen, caller, host)}"


def _rows_command(only: RowKind | None, caller: Caller, host: Host) -> str:
    # fzf does not show a reload command's stderr, so a failure becomes the header line.
    only_options = ["--only", only] if only is not None else []
    arguments = ["rows", "--picker-header", *only_options, *_host_options(host), *_caller_options(caller)]
    return f"{_self_command()} {shlex.join(arguments)}"


def _host_options(host: Host) -> list[str]:
    """Return the --host option a callback needs to drive HOST.

    The option is left out when HOST is the TUI and the callback, which
    inherits this process's environment, would default to the TUI anyway, so
    TUI pickers run the same callback commands as before --host existed.
    """
    if host == "tui" and default_host() == "tui":
        return []
    return ["--host", host]


def _caller_options(caller: Caller) -> list[str]:
    options: list[str] = []
    if caller.workspace_id != "":
        options += ["--caller-workspace", caller.workspace_id]
    if caller.pane_id != "":
        options += ["--caller-pane", caller.pane_id]
    return options


def _self_command() -> str:
    """Return this CLI as a /bin/sh command word, for fzf to call back into."""
    program = os.environ.get("HERDR_FIND_BIN", "")
    return shlex.quote(program if program != "" else PROGRAM)


def _fzf() -> str:
    fzf = os.environ.get("HERDR_FIND_FZF_PATH", "")
    return fzf if fzf != "" else "fzf"


def focus(target: Target, host: Host) -> None:
    """Move the user's focus in HOST to TARGET; raise FindError when Herdr refuses."""
    if host == "app":
        _app_focus(target)
    elif target.kind == "agent":
        _ = _herdr_text("agent", "focus", target.id)
    else:
        _ = _herdr_text("workspace", "focus", target.id)


def plugin_caller() -> Caller:
    """Return where Herdr opened the plugin pane from, per $HERDR_PLUGIN_CONTEXT_JSON.

    A missing or malformed context, or a missing field, leaves that part of
    the location unknown.
    """
    try:
        context = _object(cast(object, json.loads(os.environ.get("HERDR_PLUGIN_CONTEXT_JSON", ""))))
    except json.JSONDecodeError:
        context: dict[str, object] = {}
    return Caller(
        workspace_id=_string(context.get("workspace_id")),
        pane_id=_string(context.get("focused_pane_id")),
    )


# The desktop app host. The app window owns spaces, tabs and panes
# (``herdr-app ls``); its core owns terminals and their status reports
# (``hc``). Spaces and terminals on other machines are left out: this CLI acts
# on this machine only.


def app_terminal_caller() -> Caller:
    """Return where the CLI runs in the app: the terminal $HC_TERMINAL_ID names.

    Its space is the terminal's ``herdr.space`` label, which the app sets on
    every terminal it shows in a pane. Outside a core terminal the location is
    unknown. Raises FindError when hc cannot describe the terminal.
    """
    address = os.environ.get("HC_TERMINAL_ID", "")
    if address == "":
        return Caller()

    labels = _object(_app_json("hc", "get", address, "--json").get("labels"))
    return Caller(workspace_id=_string(labels.get("herdr.space")), pane_id=address)


@dataclass(frozen=True)
class AppTerminal:
    """A terminal shown in an app pane, from ``herdr-app ls``, with display fields sanitized.

    STATUS is the word the app's sidebar shows (working, blocked, done or
    idle), or "" when the terminal is no agent. APP is the agent's name from
    its status reports, or "" when it never gave one.
    """

    address: str
    status: str
    app: str
    name: str


@dataclass(frozen=True)
class AppTab:
    """A tab of an app space, with its pane terminals in layout order."""

    name: str
    terminals: tuple[AppTerminal, ...]


@dataclass(frozen=True)
class AppSpace:
    """A space of the app window on this machine, from ``herdr-app ls``.

    SPACE_ID is kept as the app reports it; NAME is sanitized for display.
    FOLDER is where its new terminals start.
    """

    space_id: str
    name: str
    folder: str
    tabs: tuple[AppTab, ...]


def _app_rows(*, only: RowKind | None, caller: Caller) -> list[str]:
    # The window is asked first: with no window open the call fails before hc
    # runs, and hc starts a core when none is running.
    spaces = _app_spaces()
    agents = _app_agents(spaces)

    lines: list[str] = []
    if only != "workspaces":
        names = {space.space_id: space.name for space in spaces}
        lines += _agent_rows(agents, names, caller)
    if only != "agents":
        lines += _space_rows(spaces, agents, caller)
    return lines


def _app_spaces() -> list[AppSpace]:
    """Return the app window's spaces on this machine, in sidebar order.

    Raises FindError when no app window is open.
    """
    records = _app_json("herdr-app", "ls").get("spaces")
    if not isinstance(records, list):
        raise FindError("herdr-app ls returned no spaces")

    return [
        AppSpace(
            space_id=_string(space.get("id")),
            name=sanitize(_string(space.get("name"))),
            folder=_string(space.get("folder")),
            tabs=tuple(_app_tab(tab) for tab in _objects(space.get("tabs"))),
        )
        for space in _objects(records)
        if space.get("machine") is None
    ]


def _app_tab(tab: dict[str, object]) -> AppTab:
    return AppTab(
        name=sanitize(_string(tab.get("name"))),
        terminals=tuple(
            AppTerminal(
                address=_string(terminal.get("terminal")),
                status=sanitize(_string(terminal.get("status"))),
                app=sanitize(_string(terminal.get("app"))),
                name=sanitize(_string(terminal.get("name"))),
            )
            for terminal in _objects(tab.get("terminals"))
        ),
    )


def _app_agents(spaces: Sequence[AppSpace]) -> list[Agent]:
    """Return the core's status-reporting terminals on this machine as agents.

    Sub-agents, which have no pane, belong to the space of the nearest
    ancestor terminal shown in one. A pane terminal's status is the word the
    app shows; any other's is its reported word. hc ls reports no status
    change order, so agents of one status keep hc's order.
    """
    shown = [(space.space_id, terminal) for space in spaces for tab in space.tabs for terminal in tab.terminals]
    space_ids = {terminal.address: space_id for space_id, terminal in shown}
    shown_statuses = {terminal.address: terminal.status for _space_id, terminal in shown if terminal.status != ""}

    terminals = _app_list("terminals", "hc", "ls", "--json")
    parents = {_string(terminal.get("address")): _string(terminal.get("parent")) for terminal in terminals}

    agents: list[Agent] = []
    for terminal in terminals:
        address = _string(terminal.get("address"))
        reported = sanitize(_string(terminal.get("status")))
        if address == "" or reported == "" or "/" in address:
            continue
        agents.append(
            Agent(
                pane_id=address,
                workspace_id=_app_space_id(address, space_ids, parents),
                agent=sanitize(_string(terminal.get("agent"))),
                status=shown_statuses.get(address, _app_shown_status(reported)),
                title=sanitize(_string(terminal.get("name"))),
                directory=sanitize(_home_relative(_string(terminal.get("cwd")))),
                state_change_seq=None,
            )
        )
    return agents


# How many parent links a sub-agent's space is looked up through, as the app
# itself does, so a parent cycle cannot loop forever.
_MAX_PARENT_DEPTH = 32


def _app_space_id(address: str, space_ids: dict[str, str], parents: dict[str, str]) -> str:
    """Return the space showing ADDRESS or its nearest shown ancestor, or "" when none is shown."""
    current = address
    for _ in range(_MAX_PARENT_DEPTH):
        if current in space_ids:
            return space_ids[current]
        current = parents.get(current, "")
        if current == "":
            break
    return ""


def _app_shown_status(reported: str) -> str:
    """Return the word the app shows for a REPORTED status: it shows "error" as "blocked"."""
    return "blocked" if reported == "error" else reported


def _space_rows(spaces: Sequence[AppSpace], agents: Sequence[Agent], caller: Caller) -> list[str]:
    listed = sorted(
        (space for space in spaces if space.space_id != ""),
        key=lambda space: space.space_id == caller.workspace_id,
    )
    cell_rows = [
        [
            (space.name, _BOLD),
            (sanitize(_home_relative(space.folder)), _DIM),
            (_agent_summary(space.space_id, agents), ""),
        ]
        for space in listed
    ]
    targets = [WORKSPACE_TARGET_PREFIX + sanitize(space.space_id) for space in listed]
    return _table(targets, cell_rows)


def _app_preview(target: Target) -> str:
    if target.kind == "agent":
        return _app_text("hc", "read", target.id, "--lines", str(AGENT_PREVIEW_LINES))

    space = next((space for space in _app_spaces() if space.space_id == target.id), None)
    if space is None:
        raise FindError(f"the Herdr app has no space {target.id!r}")
    return "".join(f"{line}\n" for line in _space_preview(space))


def _space_preview(space: AppSpace) -> list[str]:
    def terminal_cells(terminal: AppTerminal) -> list[_Cell]:
        return [
            (_text_or(terminal.app, "shell"), ""),
            _status_cell(_agent_status(terminal.status)),
            (terminal.name, ""),
        ]

    # Align agent and status across all of the space's terminals; the name is last.
    every_cells = [terminal_cells(terminal) for tab in space.tabs for terminal in tab.terminals]
    widths = [max((len(cells[index][0]) for cells in every_cells), default=0) for index in range(2)] + [0]

    lines = [_coloured(space.name, _BOLD)]
    if space.folder != "":
        lines.append(_coloured(sanitize(_home_relative(space.folder)), _DIM))
    for tab in space.tabs:
        lines.append(_coloured(tab.name, _BOLD))
        for terminal in tab.terminals:
            cells = zip(terminal_cells(terminal), widths, strict=True)
            padded = [_coloured(text.ljust(width), colour) for (text, colour), width in cells]
            lines.append(f"  {_COLUMN_SEPARATOR.join(padded).rstrip()}")
    return lines


def _app_focus(target: Target) -> None:
    if target.kind == "agent":
        _ = _app_text("herdr-app", "do", "agent.focus", json.dumps({"terminal": target.id}))
    else:
        _ = _app_text("herdr-app", "do", "space.select", json.dumps({"id": target.id}))


def _app_list(key: str, program: str, *arguments: str) -> list[dict[str, object]]:
    """Return the records under KEY of PROGRAM's JSON reply to ARGUMENTS."""
    records = _app_json(program, *arguments).get(key)
    if not isinstance(records, list):
        raise FindError(f"{shlex.join([program, *arguments])} returned no {key}")
    return _objects(records)


def _app_json(program: str, *arguments: str) -> dict[str, object]:
    stdout = _app_text(program, *arguments)
    try:
        return _object(cast(object, json.loads(stdout)))
    except json.JSONDecodeError as error:
        raise FindError(f"{shlex.join([program, *arguments])} returned malformed JSON") from error


def _app_text(program: str, *arguments: str) -> str:
    """Return the stdout of PROGRAM, herdr-app or hc found on PATH, for ARGUMENTS.

    Raises FindError when it fails, for example ``herdr-app`` with no app
    window open.
    """
    result = _run([program, *arguments])
    if result.returncode != 0:
        detail = _app_failure_detail(result)
        raise FindError(f"{shlex.join([program, *arguments])} failed" + (f": {detail}" if detail != "" else ""))
    return result.stdout


def _app_failure_detail(result: subprocess.CompletedProcess[str]) -> str:
    """Return why a herdr-app or hc call failed, from its stderr or else its stdout.

    herdr-app replies ``{"error": MESSAGE}`` and hc ``{"error": {"message":
    MESSAGE, ...}}``; the message is used when present, otherwise the output
    as written.
    """
    output = _text_or(result.stderr.strip(), result.stdout.strip())
    try:
        reply = _object(cast(object, json.loads(output)))
    except json.JSONDecodeError:
        return output
    error = reply.get("error")
    message = sanitize(_string(error) if isinstance(error, str) else _string(_object(error).get("message")))
    return message if message != "" else output


# The app's long-lived picker: one fzf process in a core terminal, shown by
# popup overlays, that keeps running between uses. Enter and the dismiss keys
# call back into this CLI instead of ending fzf, and the callbacks act on the
# request ``show`` last recorded in APP_PICKER_REQUEST_FILE.

APP_PICKER_SOCKET_FILE = "app-picker.sock"
APP_PICKER_REQUEST_FILE = "app-picker.json"

# The longest socket path macOS accepts: the size of sockaddr_un's sun_path.
_AF_UNIX_PATH_LIMIT = 104

# The keys that hide the app picker's popup without choosing a row.
_APP_PICKER_DISMISS_KEYS = ("esc", "ctrl-c", "ctrl-g", "ctrl-q")


def serve() -> int:
    """Run the app's long-lived picker until fzf exits; return fzf's exit status.

    fzf listens for actions on APP_PICKER_SOCKET_FILE in the picker state
    directory, created mode 0700 so only the user can drive it, and starts
    with the header line only; ``show`` loads rows into it. Enter focuses the
    current row's target and closes the recorded popup, the dismiss keys close
    it, and the reload keys use the recorded caller; none of them ends fzf.
    Raises FindError when the socket path is too long or fzf cannot run.
    """
    socket_path = _app_picker_socket_path()
    _ = _create_app_picker_state_directory()

    command = [_fzf(), *_serve_fzf_options(socket_path)]
    try:
        result = subprocess.run(command, input=f"{picker_header_line()}\n", check=False, text=True)
    except OSError as error:
        raise FindError(f"could not run {command[0]}: {error}") from error
    return result.returncode


def _serve_fzf_options(socket_path: Path) -> list[str]:
    self_command = _self_command()
    return [
        *_fzf_display_options("app"),
        f"--listen={socket_path}",
        f"--bind=enter:transform:{self_command} accept-action {{1}}",
        *(f"--bind={key}:execute-silent:{self_command} dismiss" for key in _APP_PICKER_DISMISS_KEYS),
        *(
            f"--bind={key}:transform:{self_command} request-reload-action {reload_key}"
            for key, reload_key in RELOAD_KEYS
        ),
        *_PREVIEW_KEY_OPTIONS,
    ]


def _app_picker_state_directory() -> Path:
    return Path.home() / ".local" / "state" / PROGRAM


def _app_picker_socket_path() -> Path:
    """Return the path of the app picker's fzf socket; raise FindError when macOS cannot bind it."""
    socket_path = _app_picker_state_directory() / APP_PICKER_SOCKET_FILE
    if len(os.fsencode(socket_path)) > _AF_UNIX_PATH_LIMIT:
        raise FindError(f"socket path {socket_path} is longer than {_AF_UNIX_PATH_LIMIT} bytes")
    return socket_path


def _create_app_picker_state_directory() -> Path:
    """Create the app picker's state directory, or make an existing one private (mode 0700); return it."""
    state_directory = _app_picker_state_directory()
    try:
        state_directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        state_directory.chmod(0o700)
    except OSError as error:
        raise FindError(f"could not create {state_directory}: {error}") from error
    return state_directory


@dataclass(frozen=True)
class AppPickerRequest:
    """What ``show`` asked the app picker for: the popup overlay showing it and where it was opened from."""

    overlay_id: str
    caller: Caller


def read_app_picker_request() -> AppPickerRequest | None:
    """Return the request recorded in APP_PICKER_REQUEST_FILE, or None when none is.

    A missing or malformed file, or one naming no overlay, records no request.
    Raises FindError when the file exists but cannot be read.
    """
    path = _app_picker_state_directory() / APP_PICKER_REQUEST_FILE
    try:
        text = path.read_text()
    except FileNotFoundError:
        return None
    except OSError as error:
        raise FindError(f"could not read {path}: {error}") from error

    try:
        record = _object(cast(object, json.loads(text)))
    except json.JSONDecodeError:
        return None
    overlay_id = _string(record.get("overlay"))
    if overlay_id == "":
        return None
    return AppPickerRequest(
        overlay_id=overlay_id,
        caller=Caller(
            workspace_id=_string(record.get("caller_workspace")),
            pane_id=_string(record.get("caller_pane")),
        ),
    )


def accept_action(target_text: str) -> str:
    """Return the fzf action for Enter on the app picker row whose TARGET is TARGET_TEXT.

    Focuses the target as ``pick`` does, then closes the recorded popup (the
    top dialog when no request is recorded), and clears the header line. When
    focusing fails it closes nothing; when either fails it returns an action
    that shows the error in the header line, leaving the query and rows as
    they are.
    """
    try:
        focus(parse_target(target_text), "app")
        close_app_picker_popup(read_app_picker_request())
    except FindError as error:
        return f"change-header:error: {sanitize(str(error))}"
    return "change-header:"


def close_app_picker_popup(request: AppPickerRequest | None) -> None:
    """Close REQUEST's popup overlay, or the app's top dialog when no request is recorded.

    Raises FindError when herdr-app fails.
    """
    parameters: dict[str, str] = {"id": request.overlay_id} if request is not None else {}
    _ = _app_text("herdr-app", "do", "overlay.close", json.dumps(parameters))


# How long ``show`` keeps trying to reach the app picker's socket, for a
# picker whose fzf has only just started, and how long it waits between tries.
APP_PICKER_SHOW_CONNECT_SECONDS = 3.0
_APP_PICKER_SHOW_RETRY_SECONDS = 0.05

# How long ``reset`` waits for the app picker to answer before giving up: it
# runs as a popup closes, including at app quit, so it must not linger.
_APP_PICKER_RESET_TIMEOUT_SECONDS = 0.5


def show(request: AppPickerRequest) -> None:
    """Record REQUEST and load fresh rows for its caller into the running app picker.

    The request is written to APP_PICKER_REQUEST_FILE before fzf is told
    anything, so a ``reset`` for an older popup that arrives afterwards finds
    a newer overlay recorded and leaves the new rows alone. fzf gets the
    unfiltered prompt and REQUEST's caller's rows with the first row
    selected; its query is kept, so keys typed before the rows arrive still
    filter them. Raises FindError when the request cannot be written or no
    picker answers within APP_PICKER_SHOW_CONNECT_SECONDS.
    """
    socket_path = _app_picker_socket_path()
    _write_app_picker_request(request)

    rows_command = _rows_command(None, request.caller, "app")
    action = f"change-prompt({FILTER_PROMPTS[None]})+reload-sync({rows_command})+first"
    connection = _UnixHTTPConnection(socket_path, timeout=APP_PICKER_SHOW_CONNECT_SECONDS)
    try:
        _connect_until_answered(connection, socket_path)
        _post_app_picker_action(connection, action)
    except OSError as error:
        raise FindError(f"could not send the app picker at {socket_path} its rows: {error}") from error
    finally:
        connection.close()


def _write_app_picker_request(request: AppPickerRequest) -> None:
    """Replace APP_PICKER_REQUEST_FILE with REQUEST atomically, so a reader sees the old or the new request whole."""
    state_directory = _create_app_picker_state_directory()
    record = {
        "overlay": request.overlay_id,
        "caller_workspace": request.caller.workspace_id,
        "caller_pane": request.caller.pane_id,
    }
    request_path = state_directory / APP_PICKER_REQUEST_FILE
    try:
        descriptor, temporary_name = tempfile.mkstemp(dir=state_directory, prefix=f".{APP_PICKER_REQUEST_FILE}.")
    except OSError as error:
        raise FindError(f"could not write {request_path}: {error}") from error

    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w") as temporary_file:
            json.dump(record, temporary_file)
        os.replace(temporary_path, request_path)
    except OSError as error:
        temporary_path.unlink(missing_ok=True)
        raise FindError(f"could not write {request_path}: {error}") from error


def _connect_until_answered(connection: _UnixHTTPConnection, socket_path: Path) -> None:
    """Connect CONNECTION, retrying for APP_PICKER_SHOW_CONNECT_SECONDS; raise FindError when it never connects."""
    deadline = time.monotonic() + APP_PICKER_SHOW_CONNECT_SECONDS
    while True:
        try:
            connection.connect()
            return
        except OSError as error:
            if time.monotonic() >= deadline:
                raise FindError(
                    f"no app picker answered on {socket_path} within {APP_PICKER_SHOW_CONNECT_SECONDS:g} s: {error}"
                ) from error
        time.sleep(_APP_PICKER_SHOW_RETRY_SECONDS)


def reset(overlay_id: str) -> None:
    """Clear the running app picker after OVERLAY_ID's popup closed, unless a newer popup has taken it over.

    fzf decides inside its own action loop, through ``reset-action``, so a
    ``show`` for a newer popup that recorded its request first is never
    undone. Does nothing when no picker answers within
    _APP_PICKER_RESET_TIMEOUT_SECONDS. Raises FindError when a picker answers
    but refuses the action.
    """
    socket_path = _app_picker_socket_path()
    action = f"transform:{_self_command()} {shlex.join(['reset-action', overlay_id])}"
    connection = _UnixHTTPConnection(socket_path, timeout=_APP_PICKER_RESET_TIMEOUT_SECONDS)
    try:
        connection.connect()
        _post_app_picker_action(connection, action)
    except OSError:
        return
    finally:
        connection.close()


def reset_action(overlay_id: str) -> str:
    """Return the fzf action that clears the app picker after OVERLAY_ID's popup closed, or "" to change nothing.

    The picker is cleared, its query, filter prompt and header emptied and
    its rows reloaded to the header line only, when the request file records
    OVERLAY_ID or records no request; a request for another overlay means a
    newer popup shows the picker. Raises FindError when the request file
    cannot be read.
    """
    request = read_app_picker_request()
    if request is not None and request.overlay_id != overlay_id:
        return ""
    header_command = f"{_self_command()} header"
    return f"change-query()+change-prompt({FILTER_PROMPTS[None]})+change-header()+reload-sync({header_command})"


def _post_app_picker_action(connection: _UnixHTTPConnection, action: str) -> None:
    """Send the app picker ACTION over CONNECTION.

    Raises FindError when fzf refuses it, and OSError when the connection fails.
    """
    connection.request("POST", "/", body=action.encode())
    response = connection.getresponse()
    reply = response.read().decode(errors="replace")
    if response.status != 200:
        raise FindError(f"the app picker refused {action!r} with status {response.status}: {sanitize(reply)}")


class _UnixHTTPConnection(http.client.HTTPConnection):
    """An HTTP connection to the server on the Unix socket at SOCKET_PATH, such as fzf's --listen."""

    def __init__(self, socket_path: Path, timeout: float) -> None:
        super().__init__("localhost", timeout=timeout)
        self.socket_path: Path = socket_path

    @override
    def connect(self) -> None:
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            connection.settimeout(self.timeout)
            connection.connect(str(self.socket_path))
        except OSError:
            connection.close()
            raise
        self.sock = connection


# A display cell: its sanitized text and the SGR escape that colours it, or ""
# for the terminal's default.
_Cell = tuple[str, str]

_BOLD = "\x1b[1m"
_DIM = "\x1b[2m"
_RESET = "\x1b[0m"
_ERROR_COLOUR = "\x1b[31m"
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
        raise FindError(f"{_herdr_call_text(arguments)} returned no {key}")
    return [_object(record) for record in cast(list[object], records)]


def _herdr_json(*arguments: str) -> dict[str, object]:
    stdout = _herdr_text(*arguments)
    try:
        return _object(cast(object, json.loads(stdout)))
    except json.JSONDecodeError as error:
        raise FindError(f"{_herdr_call_text(arguments)} returned malformed JSON") from error


def _herdr_text(*arguments: str) -> str:
    """Return herdr's stdout for ARGUMENTS; raise FindError when it fails."""
    result = _run([_herdr(), *arguments])
    if result.returncode != 0:
        detail = _herdr_failure_detail(result)
        raise FindError(f"{_herdr_call_text(arguments)} failed" + (f": {detail}" if detail != "" else ""))
    return result.stdout


def _herdr_call_text(arguments: Sequence[str]) -> str:
    """Return the herdr call ARGUMENTS as an error message names it, ``herdr ARGUMENTS``.

    It names herdr rather than $HERDR_BIN_PATH, often a long store path, so a
    message shown in the picker's one-line header keeps its detail in view.
    """
    return shlex.join(["herdr", *arguments])


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
    """Run COMMAND capturing stdout and stderr.

    Raises FindError naming COMMAND's program by its file name when it cannot
    run; the OS error that follows names its path.
    """
    try:
        return subprocess.run(command, check=False, capture_output=True, text=True)
    except OSError as error:
        raise FindError(f"could not run {Path(command[0]).name}: {error}") from error


def _object(value: object) -> dict[str, object]:
    return cast(dict[str, object], value) if isinstance(value, dict) else {}


def _objects(value: object) -> list[dict[str, object]]:
    """Return VALUE's objects when it is a list, each non-object as empty; else no objects."""
    return [_object(item) for item in cast(list[object], value)] if isinstance(value, list) else []


def _string(value: object) -> str:
    return value if isinstance(value, str) else ""


def _integer(value: object) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def _command_rows(arguments: argparse.Namespace) -> int:
    host = _host(arguments)
    picker_header = cast(bool, arguments.picker_header)
    try:
        listed = rows(only=cast(RowKind | None, arguments.only), caller=_caller(arguments, host), host=host)
    except FindError as error:
        if not picker_header:
            raise
        listed = [picker_error_line(str(error))]
    else:
        if picker_header:
            listed = [picker_header_line(), *listed]

    for line in listed:
        print(line)
    return 0


def _command_preview(arguments: argparse.Namespace) -> int:
    _ = sys.stdout.write(preview(parse_target(cast(str, arguments.target)), _host(arguments)))
    return 0


def _command_pick(arguments: argparse.Namespace) -> int:
    host = _host(arguments)
    caller = _caller(arguments, host)
    if host == "tui" and caller == Caller():
        caller = plugin_caller()
    pick(caller, host)
    return 0


def _command_reload_action(arguments: argparse.Namespace) -> int:
    caller = Caller(
        workspace_id=cast(str, arguments.caller_workspace),
        pane_id=cast(str, arguments.caller_pane),
    )
    prompt = os.environ.get("FZF_PROMPT", "")
    print(reload_action(cast(ReloadKey, arguments.key), prompt, caller, _host(arguments)))
    return 0


def _command_serve(_arguments: argparse.Namespace) -> int:
    return serve()


def _command_accept_action(arguments: argparse.Namespace) -> int:
    print(accept_action(cast(str, arguments.target)))
    return 0


def _command_dismiss(_arguments: argparse.Namespace) -> int:
    close_app_picker_popup(read_app_picker_request())
    return 0


def _command_request_reload_action(arguments: argparse.Namespace) -> int:
    # The caller comes from the request alone: _caller() would take the
    # picker's own terminal as the caller.
    request = read_app_picker_request()
    caller = request.caller if request is not None else Caller()
    prompt = os.environ.get("FZF_PROMPT", "")
    print(reload_action(cast(ReloadKey, arguments.key), prompt, caller, "app"))
    return 0


def _command_show(arguments: argparse.Namespace) -> int:
    caller = Caller(
        workspace_id=cast(str, arguments.caller_workspace),
        pane_id=cast(str, arguments.caller_pane),
    )
    show(AppPickerRequest(overlay_id=cast(str, arguments.overlay), caller=caller))
    return 0


def _command_reset(arguments: argparse.Namespace) -> int:
    reset(cast(str, arguments.overlay))
    return 0


def _command_reset_action(arguments: argparse.Namespace) -> int:
    action = reset_action(cast(str, arguments.overlay))
    if action != "":
        print(action)
    return 0


def _command_header(_arguments: argparse.Namespace) -> int:
    print(picker_header_line())
    return 0


def _host(arguments: argparse.Namespace) -> Host:
    chosen = cast(Host | None, arguments.host)
    return chosen if chosen is not None else default_host()


def _caller(arguments: argparse.Namespace, host: Host) -> Caller:
    """Return the location the caller options name.

    With neither option given, the app's caller is the terminal the CLI runs
    in; the TUI's stays unknown.
    """
    given = Caller(
        workspace_id=cast(str, arguments.caller_workspace),
        pane_id=cast(str, arguments.caller_pane),
    )
    if host == "app" and given == Caller():
        return app_terminal_caller()
    return given


def _command_open_popup(arguments: argparse.Namespace) -> int:
    # Keys can bind only plugin actions, and an action runs without a terminal,
    # so the action opens the picker's popup pane.
    plugin_id = os.environ.get("HERDR_PLUGIN_ID", "")
    if plugin_id == "":
        raise FindError("HERDR_PLUGIN_ID is not set; run this as a Herdr plugin action")
    command = [_herdr(), "plugin", "pane", "open", "--plugin", plugin_id]
    command += ["--entrypoint", cast(str, arguments.entrypoint), "--focus"]
    _ = sys.stdout.flush()
    try:
        return subprocess.run(command, check=False).returncode
    except OSError as error:
        raise FindError(f"could not run {command[0]}: {error}") from error


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
    _ = rows_parser.add_argument(
        "--picker-header",
        action="store_true",
        help=(
            "print the picker's header line first, a TAB then its key hints; on "
            "failure, print a TAB then the error in its place and exit 0"
        ),
    )
    _ = rows_parser.add_argument("--only", choices=("agents", "workspaces"), help="print only one group of rows")
    _ = rows_parser.add_argument(
        "--caller-workspace", metavar="ID", default="", help="workspace to list last among workspaces"
    )
    _ = rows_parser.add_argument("--caller-pane", metavar="ID", default="", help="agent pane to list last among agents")
    _add_host_argument(rows_parser)
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
    _add_host_argument(preview_parser)
    preview_parser.set_defaults(handler=_command_preview)

    pick_parser = commands.add_parser(
        "pick",
        help="plugin popup that picks an agent or workspace and focuses it",
        description=(
            "Show the picker rows in fzf, with the selected row's preview, and "
            "focus the agent pane or workspace chosen with Enter; Esc changes "
            "nothing. ctrl-a and ctrl-w show only agents or workspaces, and the "
            "same key again shows both; ctrl-r refreshes; ctrl-o toggles the "
            "preview; ctrl-u/ctrl-d scroll it. The caller's own rows sort last: "
            "those the caller options name, else in the TUI those from "
            "$HERDR_PLUGIN_CONTEXT_JSON and in the app those of the terminal "
            "$HC_TERMINAL_ID names. A failure is shown until Enter is pressed."
        ),
    )
    _ = pick_parser.add_argument(
        "--caller-workspace", metavar="ID", default="", help="workspace to list last among workspaces"
    )
    _ = pick_parser.add_argument("--caller-pane", metavar="ID", default="", help="agent pane to list last among agents")
    _add_host_argument(pick_parser)
    pick_parser.set_defaults(handler=_command_pick, popup=True)

    reload_parser = commands.add_parser(
        "reload-action",
        help="print the fzf action a picker key runs",
        description=(
            "Print the fzf action that reloads the picker rows for KEY, given the "
            "picker's current filter in $FZF_PROMPT: refresh keeps the filter; "
            "agents or workspaces shows only that group, or both when it is "
            "already the filter."
        ),
    )
    _ = reload_parser.add_argument("key", choices=("refresh", "agents", "workspaces"), metavar="KEY")
    _ = reload_parser.add_argument("--caller-workspace", metavar="ID", default="", help="workspace to list last")
    _ = reload_parser.add_argument("--caller-pane", metavar="ID", default="", help="agent pane to list last")
    _add_host_argument(reload_parser)
    reload_parser.set_defaults(handler=_command_reload_action)

    popup_parser = commands.add_parser(
        "open-popup",
        help="plugin action that opens a popup pane",
        description="Open this plugin's popup pane ENTRYPOINT in Herdr and focus it.",
    )
    _ = popup_parser.add_argument("entrypoint", metavar="ENTRYPOINT")
    popup_parser.set_defaults(handler=_command_open_popup)

    serve_parser = commands.add_parser(
        "serve",
        help="run the Herdr app's long-lived picker",
        description=(
            "Run one fzf picker that keeps running between uses, listening for "
            "actions on ~/.local/state/herdr-find/app-picker.sock; show loads "
            "rows into it and reset clears it. Enter focuses the chosen agent or "
            "space and closes the popup show recorded; Esc, ctrl-c, ctrl-g and "
            "ctrl-q close it; the other keys work as in pick. Exits with fzf's status."
        ),
    )
    _ = serve_parser.add_argument("--host", choices=("app",), required=True, help="the Herdr to drive: app")
    serve_parser.set_defaults(handler=_command_serve)

    accept_parser = commands.add_parser(
        "accept-action",
        help="print the fzf action Enter runs in the app picker",
        description=(
            "Focus TARGET in the Herdr app and close the recorded popup, then "
            "print an fzf action that clears the header line, or on failure "
            "one that shows the error there."
        ),
    )
    _ = accept_parser.add_argument("target", metavar="TARGET", help="agent:ADDRESS or workspace:SPACE_ID")
    accept_parser.set_defaults(handler=_command_accept_action)

    dismiss_parser = commands.add_parser(
        "dismiss",
        help="close the app picker's popup",
        description="Close the popup the app picker's request records, or the top dialog when none is recorded.",
    )
    dismiss_parser.set_defaults(handler=_command_dismiss)

    request_reload_parser = commands.add_parser(
        "request-reload-action",
        help="print the fzf action an app picker key runs",
        description=(
            "Print the fzf action that reloads the app picker's rows for KEY, as "
            "reload-action does, with the caller the picker's request records."
        ),
    )
    _ = request_reload_parser.add_argument("key", choices=("refresh", "agents", "workspaces"), metavar="KEY")
    request_reload_parser.set_defaults(handler=_command_request_reload_action)

    show_parser = commands.add_parser(
        "show",
        help="load fresh rows into the Herdr app's running picker",
        description=(
            "Record the popup overlay ID now showing the app picker and where it "
            "was opened from, then load that caller's rows into the picker "
            "serve runs, keeping its query, and select the first row. Fails "
            "when no picker answers within 3 seconds."
        ),
    )
    _ = show_parser.add_argument("--overlay", metavar="ID", required=True, help="the popup overlay showing the picker")
    _ = show_parser.add_argument(
        "--caller-workspace", metavar="ID", required=True, help="space to list last among spaces"
    )
    _ = show_parser.add_argument(
        "--caller-pane", metavar="ADDRESS", default="", help="terminal to list last among agents"
    )
    show_parser.set_defaults(handler=_command_show)

    reset_parser = commands.add_parser(
        "reset",
        help="clear the Herdr app's running picker after its popup closed",
        description=(
            "Clear the app picker's query, filter, header and rows after the popup "
            "overlay ID closed, unless show has since recorded another overlay. "
            "Does nothing when no picker answers."
        ),
    )
    _ = reset_parser.add_argument("--overlay", metavar="ID", required=True, help="the popup overlay that closed")
    reset_parser.set_defaults(handler=_command_reset)

    reset_action_parser = commands.add_parser(
        "reset-action",
        help="print the fzf action reset runs in the app picker",
        description=(
            "Print the fzf action that clears the app picker when its request "
            "records OVERLAY or no request; print nothing otherwise."
        ),
    )
    _ = reset_action_parser.add_argument("overlay", metavar="OVERLAY", help="the popup overlay that closed")
    reset_action_parser.set_defaults(handler=_command_reset_action)

    header_parser = commands.add_parser(
        "header",
        help="print the picker's header line",
        description="Print the picker's header line, a TAB then its key hints.",
    )
    header_parser.set_defaults(handler=_command_header)
    return parser


def _add_host_argument(parser: argparse.ArgumentParser) -> None:
    _ = parser.add_argument(
        "--host",
        choices=HOSTS,
        help=(
            "the Herdr to drive: tui, the terminal UI, or app, the desktop app, "
            "where a workspace ID is a space ID and a pane ID a terminal address "
            "(default: app in an app terminal, where $HC_TERMINAL_ID is set and "
            "$HERDR_ENV is not 1; else tui)"
        ),
    )


def main(arguments: Sequence[str] | None = None) -> int:
    """Run the CLI; return its exit status, 1 after reporting a failure.

    A popup pane closes when its command exits, so a popup command's failure
    stays on screen until Enter is pressed.
    """
    parsed = _parser().parse_args(arguments)
    handler = cast(Callable[[argparse.Namespace], int], parsed.handler)
    popup = cast(bool, getattr(parsed, "popup", False))
    try:
        return handler(parsed)
    except KeyboardInterrupt:
        return 1
    except FindError as error:
        print(f"error: {error}", file=sys.stderr)
        if not popup:
            return 1

    print("\nPress enter to close.", end="", file=sys.stderr)
    try:
        _ = input()
    except (EOFError, KeyboardInterrupt):
        pass
    return 1
