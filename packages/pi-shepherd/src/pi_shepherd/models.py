"""Durable intent and ephemeral topology. Native session data is deliberately absent."""

from dataclasses import dataclass, field
from typing import Literal

Phase = Literal["provisioning", "managed", "closing", "closed"]
Delivery = Literal["prepared", "submitted", "uncertain"]
STATUSES = ("idle", "working", "blocked", "done", "unknown")
SETTLED = ("idle", "done")
READ_SOURCES = ("visible", "recent", "recent-unwrapped", "detection")
MAX_REPLY_BYTES = 256 * 1024


@dataclass(frozen=True)
class Teammate:
    teammate_id: str
    endpoint: str
    workspace_id: str
    logical_name: str
    profile: str | None
    kind: str
    cwd: str
    phase: Phase = "provisioning"
    tab_id: str | None = None
    pane_id: str | None = None
    revision: int = 0
    created_at: str = ""
    updated_at: str = ""
    closed_at: str | None = None


@dataclass(frozen=True)
class Request:
    request_id: str
    teammate_id: str
    delivery: Delivery
    reply: str | None = field(repr=False)
    created_at: str
    replied_at: str | None


@dataclass(frozen=True)
class Pane:
    pane_id: str
    terminal_id: str
    tab_id: str
    workspace_id: str
    focused: bool
    status: str
    kind: str | None
    cwd: str | None
    name: str | None = None


@dataclass(frozen=True)
class Tab:
    tab_id: str
    workspace_id: str
    label: str
    pane_count: int
    focused: bool


@dataclass(frozen=True)
class Workspace:
    workspace_id: str
    active_tab_id: str
    tab_count: int
    pane_count: int
    focused: bool


@dataclass(frozen=True)
class Snapshot:
    workspaces: tuple[Workspace, ...]
    tabs: tuple[Tab, ...]
    panes: tuple[Pane, ...]
    agents: tuple[Pane, ...]
    focused_tab_id: str | None


@dataclass(frozen=True)
class Health:
    status: str
    action: str | None = None
    tab: Tab | None = None
    pane: Pane | None = None
    automatic: bool = False
