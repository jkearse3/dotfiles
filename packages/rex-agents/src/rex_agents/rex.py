"""Call the Rex server through the `rex` CLI, never starting a server."""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from typing import Protocol, cast


class RexError(Exception):
    """A failed `rex` call, with Rex's own message."""

    def __init__(self, message: str, *, not_found: bool = False) -> None:
        super().__init__(message)
        self.message = message
        self.not_found = not_found


@dataclass(frozen=True)
class OpenedTab:
    block: str
    window: str


@dataclass(frozen=True)
class Placement:
    """Where a block sits: its session and its tab (Rex calls a tab a window)."""

    session: str
    window: str


@dataclass(frozen=True)
class Tab:
    window: str
    label: str


class Rex(Protocol):
    """The Rex operations rex-agents uses. Each raises RexError on failure."""

    def placement(self, block: str) -> Placement: ...

    def tabs(self, session: str) -> list[Tab]:
        """Return the session's tabs in tab order."""
        ...

    def open_tab(
        self, session: str, label: str, cwd: str, command: list[str]
    ) -> OpenedTab: ...

    def move_tab_after(self, session: str, window: str, after: str) -> None: ...

    def rename_tab(self, session: str, window: str, label: str) -> None: ...

    def close_block(self, block: str) -> None: ...

    def process(self, block: str) -> dict[str, object]:
        """Return the block's `process` reply, a JSON object as Rex sent it."""
        ...

    def program_status(self, block: str) -> list[dict[str, object]]:
        """Return the block's OSC 7501 status records as Rex sent them."""
        ...

    def screen(self, block: str) -> str: ...


# `rex` exits 3 when its target does not exist.
_NOT_FOUND_STATUS = 3


class CliRex:
    """A Rex that runs the `rex` on PATH."""

    def placement(self, block: str) -> Placement:
        data = self._json("block", "inspect", block, "--json")
        return Placement(
            session=_required_string(data, "session_id"),
            window=_required_string(_object(data.get("block")), "window_id"),
        )

    def tabs(self, session: str) -> list[Tab]:
        data = self._json("window", "ls", "-s", session, "--json")
        return [
            Tab(window=_required_string(w, "window_id"), label=_string(w.get("label")))
            for w in _objects(data.get("windows"))
        ]

    def open_tab(
        self, session: str, label: str, cwd: str, command: list[str]
    ) -> OpenedTab:
        data = self._json(
            "window", "new", label, "-s", session, "-c", cwd,
            "--keep-open", "--focus=false", "--json", "--", *command,
        )  # fmt: skip
        blocks = [b for b in _list(data.get("block_ids")) if isinstance(b, str)]
        if len(blocks) == 0:
            raise RexError("rex window new: unreadable output: no block_ids")
        return OpenedTab(block=blocks[0], window=_required_string(data, "window_id"))

    def move_tab_after(self, session: str, window: str, after: str) -> None:
        _ = self._run("window", "move", "-s", session, window, "--after", after)

    def rename_tab(self, session: str, window: str, label: str) -> None:
        _ = self._run("window", "rename", "-s", session, window, label)

    def close_block(self, block: str) -> None:
        _ = self._run("block", "close", block)

    def process(self, block: str) -> dict[str, object]:
        return self._json("block", "call", "-b", block, "process")

    def program_status(self, block: str) -> list[dict[str, object]]:
        return _objects(self._json("block", "call", "-b", block, "program_status").get("records"))

    def screen(self, block: str) -> str:
        return self._run("block", "capture", "-b", block, "--trim")

    def _json(self, *args: str) -> dict[str, object]:
        """Run `rex ARGS` and return the JSON object it prints.

        Raises RexError when the output is not a JSON object.
        """
        output = self._run(*args)
        try:
            data = cast(object, json.loads(output))
        except json.JSONDecodeError as error:
            raise RexError(f"rex {args[0]} {args[1]}: unreadable output: {error}")
        if not isinstance(data, dict):
            raise RexError(f"rex {args[0]} {args[1]}: unreadable output: not a JSON object")
        return cast(dict[str, object], data)

    def _run(self, *args: str) -> str:
        try:
            completed = subprocess.run(
                ["rex", "--autostart=false", *args],
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError as error:
            raise RexError(f"cannot run rex: {error}") from error
        if completed.returncode == 0:
            return completed.stdout
        lines = [line for line in completed.stderr.splitlines() if line.strip() != ""]
        message = lines[0].removeprefix("Error: ") if len(lines) > 0 else ""
        if message == "":
            message = f"rex exited with status {completed.returncode}"
        raise RexError(
            message,
            not_found=completed.returncode == _NOT_FOUND_STATUS
            or "not found" in message,
        )


# Rex replies are JSON whose shape this module checks only as far as it reads
# it: a missing or mistyped field it needs raises RexError, one it can do
# without reads as empty.
def _required_string(data: dict[str, object], key: str) -> str:
    value = data.get(key)
    if not isinstance(value, str):
        raise RexError(f"rex: unreadable output: no string {key}")
    return value


def _string(value: object) -> str:
    return value if isinstance(value, str) else ""


def _object(value: object) -> dict[str, object]:
    return cast(dict[str, object], value) if isinstance(value, dict) else {}


def _list(value: object) -> list[object]:
    return cast(list[object], value) if isinstance(value, list) else []


def _objects(value: object) -> list[dict[str, object]]:
    """Return VALUE's objects when it is a list, each non-object as empty."""
    return [_object(item) for item in _list(value)]
