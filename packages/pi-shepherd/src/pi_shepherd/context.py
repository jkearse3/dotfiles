"""Resolve the caller's stable terminal against fresh topology, not inherited routing IDs."""

import os
from dataclasses import dataclass

from .errors import require
from .herdr import Herdr
from .models import Pane, Snapshot


@dataclass(frozen=True)
class Context:
    endpoint: str
    caller: Pane
    snapshot: Snapshot


def discover(runtime: Herdr, *, compatibility: bool = True) -> Context:
    environment = runtime.environment
    socket = environment.get("HERDR_SOCKET_PATH", "")
    require(
        environment.get("HERDR_ENV") == "1"
        and os.path.isabs(socket)
        and "\0" not in socket,
        "not_in_herdr",
        "Run inside a managed Herdr pane with an absolute endpoint",
    )
    if compatibility:
        runtime.compatibility()
    current = runtime.current()
    snapshot = runtime.snapshot()
    matches = [
        pane for pane in snapshot.panes if pane.terminal_id == current.terminal_id
    ]
    require(
        len(matches) == 1,
        "context",
        "Current terminal is absent or ambiguous in fresh topology",
    )
    return Context(
        endpoint="socket:" + os.path.realpath(socket),
        caller=matches[0],
        snapshot=snapshot,
    )
