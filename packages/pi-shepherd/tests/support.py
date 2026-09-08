"""Disposable domain fake: never discovers the user's environment or Herdr server."""

# unittest initializes fixture attributes in setUp, not __init__.
# pyright: reportUninitializedInstanceVariable=false

import tempfile
import unittest
from collections.abc import Callable, Sequence
from dataclasses import replace
from pathlib import Path
from typing import override

from pi_shepherd.config import Config, parse_config
from pi_shepherd.errors import TeamError
from pi_shepherd.herdr import Herdr
from pi_shepherd.locks import Locks
from pi_shepherd.models import Pane, Request, Snapshot, Tab, Teammate, Workspace
from pi_shepherd.registry import Registry
from pi_shepherd.teammates import Team


class FakeHerdr(Herdr):
    def __init__(self, cwd: str) -> None:
        super().__init__(
            executable="NEVER-INVOKE",
            environment={
                "HERDR_ENV": "1",
                "HERDR_SOCKET_PATH": "/disposable/herdr.sock",
                "PI_PROVIDER": "test-provider",
                "PI_MODEL": "test-model",
                "PI_REASONING_LEVEL": "medium",
                "PWD": cwd,
            },
        )
        self.caller_id: str = "w1:p1"
        self.panes: list[Pane] = [
            Pane("w1:p1", "term1", "w1:t1", "w1", True, "idle", "pi", cwd)
        ]
        self.agents: list[Pane] = []
        self.tabs: list[Tab] = [Tab("w1:t1", "w1", "caller", 1, True)]
        self.calls: list[str] = []
        self.failure: str | None = None
        self.after_prompt: Callable[[str], None] | None = None
        self.counter: int = 1
        self.is_shell_ready: bool = True

    @override
    def run(
        self, args: Sequence[str], *, mutation: bool = False, timeout: float = 30
    ) -> str:
        raise AssertionError(f"FakeHerdr must not invoke external commands: {args!r}")

    @override
    def attach(self, pane: Pane) -> int:
        raise AssertionError("FakeHerdr must not attach to a live terminal")

    @override
    def compatibility(self) -> None:
        pass

    @override
    def current(self) -> Pane:
        return next(p for p in self.panes if p.pane_id == self.caller_id)

    @override
    def snapshot(self) -> Snapshot:
        spaces = sorted({tab.workspace_id for tab in self.tabs})
        workspaces = tuple(
            Workspace(
                workspace_id=space,
                active_tab_id=next(
                    t.tab_id for t in self.tabs if t.workspace_id == space
                ),
                tab_count=sum(t.workspace_id == space for t in self.tabs),
                pane_count=sum(p.workspace_id == space for p in self.panes),
                focused=space == "w1",
            )
            for space in spaces
        )
        return Snapshot(
            workspaces, tuple(self.tabs), tuple(self.panes), tuple(self.agents), "w1:t1"
        )

    def effect(self, name: str) -> None:
        self.calls.append(name)
        if self.failure == name:
            raise TeamError("transport", "Simulated uncertain effect", uncertain=True)
        if self.failure == name + "_rejected":
            raise TeamError("herdr_rejected", "Simulated definite rejection")

    @override
    def create_tab(
        self,
        workspace: str,
        cwd: str,
        label: str,
        environment: Sequence[tuple[str, str]],
    ) -> tuple[Tab, Pane]:
        self.effect("create")
        self.counter += 1
        tab = Tab(f"{workspace}:t{self.counter}", workspace, label, 1, False)
        pane = Pane(
            f"{workspace}:p{self.counter}",
            f"term{self.counter}",
            tab.tab_id,
            workspace,
            False,
            "unknown",
            None,
            cwd,
        )
        self.tabs.append(tab)
        self.panes.append(pane)
        return tab, pane

    @override
    def start(
        self, pane: Pane, name: str, kind: str, args: Sequence[str], timeout: int
    ) -> Pane:
        self.effect("start")
        agent = replace(pane, name=name, kind=kind, status="idle")
        self.agents.append(agent)
        self.panes = [
            replace(agent, name=None) if p.pane_id == pane.pane_id else p
            for p in self.panes
        ]
        return agent

    @override
    def prompt(self, pane: Pane, text: str) -> None:
        self.effect("prompt")
        if self.after_prompt:
            self.after_prompt(text)

    @override
    def close_tab(self, tab: Tab) -> None:
        self.effect("close")
        self.tabs = [t for t in self.tabs if t.tab_id != tab.tab_id]
        self.panes = [p for p in self.panes if p.tab_id != tab.tab_id]
        self.agents = [p for p in self.agents if p.tab_id != tab.tab_id]

    @override
    def rename(self, tab: Tab, label: str) -> None:
        self.effect("rename")
        self.tabs = [
            replace(t, label=label) if t.tab_id == tab.tab_id else t for t in self.tabs
        ]

    @override
    def shell_ready(self, pane: Pane) -> bool:
        return self.is_shell_ready

    @override
    def focus(self, pane: Pane) -> None:
        self.effect("focus")

    @override
    def read(self, pane: Pane, source: str, lines: int, ansi: bool) -> str:
        return "unverified terminal\n"

    def missing_agent(self) -> None:
        self.agents = []
        self.panes = [
            replace(p, kind=None, name=None, status="unknown") for p in self.panes
        ]

    def set_status(self, status: str) -> None:
        self.agents = [replace(p, status=status) for p in self.agents]
        self.panes = [replace(p, status=status) if p.kind else p for p in self.panes]


class TeamCase(unittest.TestCase):
    directory: tempfile.TemporaryDirectory[str]
    root: Path
    registry: Registry
    runtime: FakeHerdr
    config: Config
    locks: Locks
    team: Team

    @override
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.registry = Registry(self.root / "state/registry.sqlite3")
        self.addCleanup(self.registry.close)
        self.runtime = FakeHerdr(str(self.root))
        self.config = parse_config(
            {
                "profiles": {
                    "configured": {
                        "args": ["--model", "configured-model"],
                        "env": {"MODE": "configured"},
                    }
                }
            }
        )
        self.locks = Locks(self.root / "locks", timeout=0.1)
        self.team = Team(self.registry, self.runtime, self.locks, self.config)

    def create(self, name: str = "worker") -> Teammate:
        view = self.team.create(name, None, None, 4)
        teammate_id = view["teammate_id"]
        assert isinstance(teammate_id, str)
        return self.registry.get(teammate_id)

    def create_profile(self, name: str = "worker") -> Teammate:
        view = self.team.create(name, "configured", None, 4)
        teammate_id = view["teammate_id"]
        assert isinstance(teammate_id, str)
        return self.registry.get(teammate_id)

    def pending_request(self, teammate_id: str) -> Request:
        request = self.registry.slot(teammate_id)
        assert request is not None, "Expected an occupied request slot"
        return request
