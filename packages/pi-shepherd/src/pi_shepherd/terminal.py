"""Explicitly unverified terminal observation and exact-target interaction."""

import time

from .errors import present
from .models import SETTLED
from .teammates import Team


def wait(
    team: Team, reference: str, until: str | None, timeout: int
) -> dict[str, object]:
    deadline = time.monotonic() + timeout
    while True:
        with team.locked(reference) as record:
            record, health, _ = team.healthy(record)
            pane = present(health.pane)
            if (
                pane.status == until
                if until is not None
                else pane.status in (*SETTLED, "blocked")
            ):
                return {"teammate_id": record.teammate_id, "status": pane.status}
        if time.monotonic() >= deadline:
            return {"teammate_id": record.teammate_id, "status": "timeout"}
        time.sleep(min(0.1, max(0, deadline - time.monotonic())))


def read(
    team: Team, reference: str, source: str, lines: int, ansi: bool
) -> dict[str, object]:
    with team.locked(reference) as record:
        record, health, _ = team.healthy(record)
        pane = present(health.pane)
        return {
            "teammate_id": record.teammate_id,
            "source": "terminal",
            "attribution": "unverified",
            "completeness": "unknown",
            "content": team.runtime.read(pane, source, lines, ansi),
        }


def focus(team: Team, reference: str) -> dict[str, object]:
    with team.locked(reference) as record:
        record, health, _ = team.healthy(record)
        team.runtime.focus(present(health.pane))
        return {"teammate_id": record.teammate_id, "focused": True}


def attach(team: Team, reference: str) -> int:
    with team.locked(reference) as record:
        _, health, _ = team.healthy(record)
        pane = present(health.pane)
    # Never retain a cooperative lock for an unbounded interactive terminal session.
    return team.runtime.attach(pane)
