"""A fake Rex and clock for rex-agents tests, so no Rex server is involved."""

from __future__ import annotations

import io
import json
import os
import tempfile
import threading
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import TypedDict, cast

from rex_agents.cli import main
from rex_agents.rex import OpenedTab, Placement, RexError, Tab

SESSION = "session:1"
PARENT = "block:00000000-0000-0000-0000-0000000000ff"
PARENT_WINDOW = "window:parent"
START_TIME = 1_800_000_000.0


@dataclass
class FakeBlock:
    window: str
    process: dict[str, object] = field(default_factory=dict)
    records: list[dict[str, object]] = field(default_factory=list)
    screen: str = ""


class OpenCall(TypedDict):
    """One `open_tab` call FakeRex served."""

    block: str
    label: str
    cwd: str
    command: list[str]


class StartedHelper(TypedDict):
    """The JSON object `rex-agents start` prints."""

    name: str
    harness: str
    block: str
    dir: str
    result: str


class FakeRex:
    """Serves blocks and tabs from memory; records every change asked of it."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.blocks: dict[str, FakeBlock] = {PARENT: FakeBlock(PARENT_WINDOW)}
        self.tabs_in_order: list[Tab] = [Tab(PARENT_WINDOW, "parent")]
        self.opened: list[OpenCall] = []
        self.closed: list[str] = []
        self.failing: set[str] = set()
        self.count = 0

    # Test helpers.

    def add_tab(self, label: str) -> str:
        with self.lock:
            self.count += 1
            window = f"window:{self.count}"
            self.tabs_in_order.append(Tab(window, label))
            return window

    def label(self, block: str) -> str:
        window = self.blocks[block].window
        return next(t.label for t in self.tabs_in_order if t.window == window)

    def set_status(self, block: str, state: str, updated_at: str, **extra: object) -> None:
        self.blocks[block].records = [{"state": state, "updated_at": updated_at, **extra}]

    def exit(self, block: str, code: int, error: str | None = None) -> None:
        last_exit: dict[str, object] = {"exit_code": code}
        if error is not None:
            last_exit["error"] = error
        self.blocks[block].process = {"last_exit": last_exit}

    def gone(self, block: str) -> None:
        _ = self.blocks.pop(block, None)

    def _check(self, method: str) -> None:
        if method in self.failing:
            raise RexError(f"{method} failed")

    def _block(self, block: str) -> FakeBlock:
        if block not in self.blocks:
            raise RexError(f'block target "{block}" not found', not_found=True)
        return self.blocks[block]

    # The Rex protocol.

    def placement(self, block: str) -> Placement:
        self._check("placement")
        return Placement(SESSION, self._block(block).window)

    def tabs(self, session: str) -> list[Tab]:
        self._check("tabs")
        return list(self.tabs_in_order)

    def open_tab(self, session: str, label: str, cwd: str, command: list[str]) -> OpenedTab:
        self._check("open_tab")
        window = self.add_tab(label)
        with self.lock:
            block = f"block:{self.count:04x}"
            self.blocks[block] = FakeBlock(window)
            self.opened.append({"block": block, "label": label, "cwd": cwd, "command": command})
        return OpenedTab(block, window)

    def move_tab_after(self, session: str, window: str, after: str) -> None:
        self._check("move_tab_after")
        with self.lock:
            tab = next(t for t in self.tabs_in_order if t.window == window)
            self.tabs_in_order.remove(tab)
            index = next(i for i, t in enumerate(self.tabs_in_order) if t.window == after)
            self.tabs_in_order.insert(index + 1, tab)

    def rename_tab(self, session: str, window: str, label: str) -> None:
        self._check("rename_tab")
        self.tabs_in_order = [
            Tab(t.window, label) if t.window == window else t for t in self.tabs_in_order
        ]

    def close_block(self, block: str) -> None:
        self._check("close_block")
        found = self._block(block)
        del self.blocks[block]
        self.closed.append(block)
        if not any(b.window == found.window for b in self.blocks.values()):
            self.tabs_in_order = [t for t in self.tabs_in_order if t.window != found.window]

    def process(self, block: str) -> dict[str, object]:
        self._check("process")
        return self._block(block).process

    def program_status(self, block: str) -> list[dict[str, object]]:
        self._check("program_status")
        return self._block(block).records

    def screen(self, block: str) -> str:
        self._check("screen")
        return self._block(block).screen


class StopWatch(Exception):
    """Raised by FakeClock when a test lets a watch run too long."""


class FakeClock:
    """Starts at START_TIME; each sleep advances it and runs that sleep's hook."""

    def __init__(self, now: float = START_TIME) -> None:
        self.time = now
        self.sleeps = 0
        self.hooks: dict[int, Callable[[], None]] = {}
        self.max_sleeps = 60

    def now(self) -> float:
        return self.time

    def sleep(self, seconds: float) -> None:
        self.sleeps += 1
        if self.sleeps > self.max_sleeps:
            raise StopWatch
        self.time += seconds
        hook = self.hooks.get(self.sleeps)
        if hook is not None:
            hook()


class Harness:
    """Runs rex-agents in-process against FakeRex, FakeClock, and a temp tree."""

    def __init__(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "work").mkdir()
        self.rex = FakeRex()
        self.clock = FakeClock()

    def cleanup(self) -> None:
        self.tmp.cleanup()

    def env(self, parent: str = PARENT) -> dict[str, str]:
        return {
            "REX_BLOCK": parent,
            "XDG_STATE_HOME": str(self.root / "state"),
            "TMPDIR": str(self.root / "tmp"),
            "HOME": str(self.root),
        }

    def run(self, *argv: str, stdin: str = "", parent: str = PARENT) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        status = main(
            list(argv),
            env=self.env(parent),
            rex=self.rex,
            clock=self.clock,
            stdin=io.StringIO(stdin),
            out=out,
            err=err,
        )
        return status, out.getvalue(), err.getvalue()

    def start(self, name: str = "probe", harness: str = "claude") -> StartedHelper:
        status, out, err = self.run(
            "start", name, "--harness", harness, "--task", "Do it.", "-C", str(self.root / "work")
        )
        assert status == 0, err
        return cast(StartedHelper, json.loads(out))

    def write_result(self, helper: StartedHelper, text: str = "result\n", age: float = 10) -> None:
        path = Path(helper["result"])
        _ = path.write_text(text)
        stamp = self.clock.now() - age
        os.utime(path, (stamp, stamp))

    def watch(self, *argv: str) -> tuple[int, list[str]]:
        status, out, err = self.run("watch", *argv)
        return status, out.splitlines()
