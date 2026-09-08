"""Small protocol-22 boundary. Decode only required fields and never echo wire data."""

# Pure validators intentionally discard validated values not needed by the domain.
# pyright: reportUnusedCallResult=false

import json
import os
import subprocess
from collections.abc import Mapping, Sequence
from typing import cast

from .errors import TeamError, require
from .models import STATUSES, Pane, Snapshot, Tab, Workspace

HERDR_PROTOCOL = 22
HERDR_SCHEMA_VERSION = 1

REQUIRED_METHODS = {
    "session.snapshot",
    "pane.current",
    "pane.process_info",
    "tab.create",
    "tab.rename",
    "tab.close",
    "agent.start",
    "agent.prompt",
    "agent.read",
    "agent.focus",
}


def obj(value: object) -> Mapping[str, object]:
    require(isinstance(value, dict), "protocol", "Expected Herdr object")
    return cast(dict[str, object], value)


def array(value: object) -> list[object]:
    require(isinstance(value, list), "protocol", "Expected Herdr array")
    return cast(list[object], value)


def string(value: object) -> str:
    require(
        isinstance(value, str) and bool(value) and "\0" not in value,
        "protocol",
        "Expected nonempty Herdr text",
    )
    return cast(str, value)


def optional(value: object) -> str | None:
    return None if value is None else string(value)


def boolean(value: object) -> bool:
    require(type(value) is bool, "protocol", "Expected Herdr boolean")
    return cast(bool, value)


def number(value: object) -> int:
    require(
        type(value) is int and value >= 0,
        "protocol",
        "Expected nonnegative Herdr integer",
    )
    return cast(int, value)


def status(value: object) -> str:
    require(value in STATUSES, "protocol", "Unsupported Herdr status")
    return cast(str, value)


def decode_pane(value: object) -> Pane:
    raw = obj(value)
    number(raw.get("revision"))
    foreground = optional(raw.get("foreground_cwd"))
    cwd = optional(raw.get("cwd"))
    return Pane(
        pane_id=string(raw.get("pane_id")),
        terminal_id=string(raw.get("terminal_id")),
        tab_id=string(raw.get("tab_id")),
        workspace_id=string(raw.get("workspace_id")),
        focused=boolean(raw.get("focused")),
        status=status(raw.get("agent_status")),
        kind=optional(raw.get("agent")),
        cwd=foreground or cwd,
        name=optional(raw.get("name")),
    )


def decode_tab(value: object) -> Tab:
    raw = obj(value)
    number(raw.get("number"))
    status(raw.get("agent_status"))
    return Tab(
        tab_id=string(raw.get("tab_id")),
        workspace_id=string(raw.get("workspace_id")),
        label=string(raw.get("label")),
        pane_count=number(raw.get("pane_count")),
        focused=boolean(raw.get("focused")),
    )


def unique(values: Sequence[str]) -> None:
    require(len(set(values)) == len(values), "protocol", "Duplicate Herdr identity")


def decode_snapshot(value: object) -> Snapshot:
    raw = obj(value)
    string(raw.get("version"))
    require(
        number(raw.get("protocol")) == HERDR_PROTOCOL,
        "protocol",
        "Unsupported Herdr protocol",
    )
    array(raw.get("layouts"))
    workspaces: list[Workspace] = []
    for workspace_value in array(raw.get("workspaces")):
        workspace = obj(workspace_value)
        number(workspace.get("number"))
        string(workspace.get("label"))
        status(workspace.get("agent_status"))
        workspaces.append(
            Workspace(
                workspace_id=string(workspace.get("workspace_id")),
                active_tab_id=string(workspace.get("active_tab_id")),
                tab_count=number(workspace.get("tab_count")),
                pane_count=number(workspace.get("pane_count")),
                focused=boolean(workspace.get("focused")),
            )
        )
    tabs = tuple(decode_tab(item) for item in array(raw.get("tabs")))
    panes = tuple(decode_pane(item) for item in array(raw.get("panes")))
    agents = tuple(decode_pane(item) for item in array(raw.get("agents")))
    for values in (
        [w.workspace_id for w in workspaces],
        [t.tab_id for t in tabs],
        [p.pane_id for p in panes],
        [p.terminal_id for p in panes],
        [p.pane_id for p in agents],
    ):
        unique(values)
    for workspace in workspaces:
        own_tabs = [t for t in tabs if t.workspace_id == workspace.workspace_id]
        own_panes = [p for p in panes if p.workspace_id == workspace.workspace_id]
        require(
            workspace.tab_count == len(own_tabs)
            and workspace.pane_count == len(own_panes)
            and any(t.tab_id == workspace.active_tab_id for t in own_tabs),
            "protocol",
            "Inconsistent Herdr workspace topology",
        )
    for tab in tabs:
        require(
            any(w.workspace_id == tab.workspace_id for w in workspaces)
            and tab.pane_count == sum(p.tab_id == tab.tab_id for p in panes),
            "protocol",
            "Inconsistent Herdr tab topology",
        )
    for pane in panes:
        require(
            any(
                t.tab_id == pane.tab_id and t.workspace_id == pane.workspace_id
                for t in tabs
            ),
            "protocol",
            "Inconsistent Herdr pane topology",
        )
    for agent in agents:
        matches = [p for p in panes if p.pane_id == agent.pane_id]
        require(len(matches) == 1, "protocol", "Agent pane is absent")
        pane = matches[0]
        require(
            (pane.terminal_id, pane.tab_id, pane.workspace_id, pane.focused)
            == (agent.terminal_id, agent.tab_id, agent.workspace_id, agent.focused)
            and (pane.kind is None or pane.kind == agent.kind),
            "protocol",
            "Inconsistent Herdr agent identity",
        )

    focus = tuple(
        optional(raw.get(key))
        for key in ("focused_workspace_id", "focused_tab_id", "focused_pane_id")
    )
    flagged = (
        [w.workspace_id for w in workspaces if w.focused],
        [t.tab_id for t in tabs if t.focused],
        [p.pane_id for p in panes if p.focused],
    )
    require(
        all(not group for group in flagged)
        if focus == (None, None, None)
        else all(
            value is not None and group == [value]
            for group, value in zip(flagged, focus)
        ),
        "protocol",
        "Inconsistent Herdr focus flags",
    )
    if focus[0] is not None:
        require(
            any(
                p.pane_id == focus[2]
                and p.tab_id == focus[1]
                and p.workspace_id == focus[0]
                for p in panes
            )
            and any(
                w.workspace_id == focus[0] and w.active_tab_id == focus[1]
                for w in workspaces
            ),
            "protocol",
            "Inconsistent Herdr focused hierarchy",
        )
    return Snapshot(
        workspaces=tuple(workspaces),
        tabs=tabs,
        panes=panes,
        agents=agents,
        focused_tab_id=focus[1],
    )


def same_binding(left: Pane, right: Pane) -> bool:
    return (
        left.pane_id,
        left.terminal_id,
        left.tab_id,
        left.workspace_id,
        left.kind,
        left.name,
    ) == (
        right.pane_id,
        right.terminal_id,
        right.tab_id,
        right.workspace_id,
        right.kind,
        right.name,
    )


class Herdr:
    def __init__(
        self, executable: str = "herdr", environment: Mapping[str, str] | None = None
    ) -> None:
        self.executable: str = executable
        self.environment: dict[str, str] = dict(
            os.environ if environment is None else environment
        )

    def run(
        self, args: Sequence[str], *, mutation: bool = False, timeout: float = 30
    ) -> str:
        try:
            result = subprocess.run(
                [self.executable, *args],
                capture_output=True,
                env=self.environment,
                timeout=timeout,
                check=False,
            )
        except OSError as error:
            raise TeamError(
                "herdr_unavailable", "Could not launch Herdr client"
            ) from error
        except subprocess.TimeoutExpired as error:
            raise TeamError(
                "herdr_timeout",
                "Herdr client timed out; do not replay effects",
                uncertain=mutation,
            ) from error
        if result.returncode:
            raise TeamError(
                "herdr_rejected" if result.returncode == 2 else "herdr_error",
                "Herdr command failed; inspect current state",
                uncertain=mutation and result.returncode != 2,
            )
        try:
            return result.stdout.decode("utf-8")
        except UnicodeError as error:
            raise TeamError(
                "protocol", "Malformed Herdr text", uncertain=mutation
            ) from error

    def call(
        self,
        args: Sequence[str],
        expected: str,
        *,
        mutation: bool = False,
        timeout: float = 30,
    ) -> Mapping[str, object]:
        text = self.run(args, mutation=mutation, timeout=timeout)
        try:
            payload = obj(cast(object, json.loads(text)))
            string(payload.get("id"))
            require(
                "error" not in payload, "protocol", "Unexpected Herdr error envelope"
            )
            result = obj(payload.get("result"))
            require(
                result.get("type") == expected,
                "protocol",
                "Unexpected Herdr response type",
            )
            return result
        except (ValueError, TeamError) as error:
            raise TeamError(
                "protocol", "Malformed Herdr response", uncertain=mutation
            ) from error

    def compatibility(self) -> None:
        try:
            raw = obj(cast(object, json.loads(self.run(("api", "schema", "--json")))))
            require(
                number(raw.get("protocol")) == HERDR_PROTOCOL
                and number(raw.get("schema_version")) == HERDR_SCHEMA_VERSION,
                "protocol",
                "Unsupported Herdr API schema",
            )
            request = obj(obj(raw.get("schemas")).get("request"))
            methods = {
                string(obj(obj(obj(v).get("properties")).get("method")).get("const"))
                for v in array(request.get("oneOf"))
            }
            require(
                REQUIRED_METHODS <= methods, "protocol", "Herdr lacks required methods"
            )
        except ValueError as error:
            raise TeamError("protocol", "Malformed Herdr API schema") from error

    def snapshot(self) -> Snapshot:
        return decode_snapshot(
            self.call(("api", "snapshot"), "session_snapshot").get("snapshot")
        )

    def current(self) -> Pane:
        return decode_pane(
            self.call(("pane", "current", "--current"), "pane_current").get("pane")
        )

    def create_tab(
        self,
        workspace: str,
        cwd: str,
        label: str,
        environment: Sequence[tuple[str, str]],
    ) -> tuple[Tab, Pane]:
        args = [
            "tab",
            "create",
            "--workspace",
            workspace,
            "--cwd",
            cwd,
            "--label",
            label,
            "--no-focus",
        ]
        for key, value in environment:
            args.extend(("--env", key + "=" + value))
        result = self.call(args, "tab_created", mutation=True)
        try:
            return decode_tab(result.get("tab")), decode_pane(result.get("root_pane"))
        except TeamError as error:
            raise TeamError(
                "protocol", "Malformed created topology", uncertain=True
            ) from error

    def start(
        self, pane: Pane, name: str, kind: str, args: Sequence[str], timeout: int
    ) -> Pane:
        result = self.call(
            (
                "agent",
                "start",
                name,
                "--kind",
                kind,
                "--pane",
                pane.pane_id,
                "--timeout",
                str(timeout * 1000),
                "--",
                *args,
            ),
            "agent_started",
            mutation=True,
            timeout=timeout + 5,
        )
        try:
            require(
                all(isinstance(a, str) for a in array(result.get("argv"))),
                "protocol",
                "Malformed start argv",
            )
            agent = decode_pane(result.get("agent"))
            require(
                agent.pane_id == pane.pane_id
                and agent.terminal_id == pane.terminal_id
                and agent.tab_id == pane.tab_id
                and agent.workspace_id == pane.workspace_id
                and agent.kind == kind
                and agent.name == name,
                "protocol",
                "Wrong started binding",
            )
            return agent
        except TeamError as error:
            raise TeamError(
                "protocol", "Unverified started binding", uncertain=True
            ) from error

    def prompt(self, pane: Pane, text: str) -> None:
        result = self.call(
            ("agent", "prompt", pane.pane_id, text), "agent_prompted", mutation=True
        )
        self.check_agent_response(result, pane)

    def check_agent_response(self, result: Mapping[str, object], pane: Pane) -> None:
        try:
            require(
                same_binding(decode_pane(result.get("agent")), pane),
                "protocol",
                "Wrong agent binding",
            )
        except TeamError as error:
            raise TeamError(
                "protocol", "Unverified operation binding", uncertain=True
            ) from error

    def read(self, pane: Pane, source: str, lines: int, ansi: bool) -> str:
        args = [
            "agent",
            "read",
            pane.pane_id,
            "--source",
            source,
            "--lines",
            str(lines),
        ]
        if ansi:
            args.append("--ansi")
        return self.run(args)

    def focus(self, pane: Pane) -> None:
        result = self.call(
            ("agent", "focus", pane.pane_id), "agent_info", mutation=True
        )
        self.check_agent_response(result, pane)

    def rename(self, tab: Tab, label: str) -> None:
        result = self.call(
            ("tab", "rename", tab.tab_id, label), "tab_info", mutation=True
        )
        try:
            changed = decode_tab(result.get("tab"))
            require(
                changed.tab_id == tab.tab_id
                and changed.workspace_id == tab.workspace_id
                and changed.label == label,
                "protocol",
                "Wrong renamed tab",
            )
        except TeamError as error:
            raise TeamError(
                "protocol", "Unverified renamed binding", uncertain=True
            ) from error

    def close_tab(self, tab: Tab) -> None:
        self.call(("tab", "close", tab.tab_id), "ok", mutation=True)

    def shell_ready(self, pane: Pane) -> bool:
        result = self.call(
            ("pane", "process-info", "--pane", pane.pane_id), "pane_process_info"
        )
        raw = obj(result.get("process_info"))
        require(
            string(raw.get("pane_id")) == pane.pane_id,
            "protocol",
            "Wrong process-info pane",
        )
        shell = raw.get("shell_pid")
        foreground = raw.get("foreground_process_group_id")
        processes = array(raw.get("foreground_processes"))
        return (
            type(shell) is int
            and shell > 0
            and shell == foreground
            and len(processes) == 1
            and obj(processes[0]).get("pid") == shell
        )

    def attach(self, pane: Pane) -> int:
        require(
            os.isatty(0) and os.isatty(1), "interactive", "attach requires a terminal"
        )
        return subprocess.call(
            [self.executable, "agent", "attach", pane.pane_id], env=self.environment
        )
