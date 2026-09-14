"""Explicitly unverified terminal observation and exact-target interaction."""

from .errors import TeamError, present, require
from .herdr import same_binding
from .models import SETTLED, Pane
from .teammates import Team


def wait(
    team: Team, reference: str, until: str | None, timeout: int
) -> dict[str, object]:
    """Block on Herdr status events and return separately labeled wait state."""
    targets = (until,) if until is not None else (*SETTLED, "blocked")
    with team.locked(reference) as record:
        record, health, _ = team.healthy(
            record,
            initial_snapshot=team.context.snapshot,
        )
        pane = present(health.pane)
        if pane.status in targets:
            return {
                "teammate_id": record.teammate_id,
                "status": pane.status,
                "wait_outcome": "matched",
                "runtime_status": pane.status,
                "runtime_health": health.status,
            }

    matched: Pane | None = None
    wait_error: TeamError | None = None
    try:
        matched = team.runtime.wait_agent(pane, targets, timeout)
    except TeamError as error:
        wait_error = error

    with team.locked(record.teammate_id) as current:
        current, health, _ = team.healthy(
            current,
            initial_snapshot=team.context.snapshot,
        )
        if wait_error is not None:
            raise wait_error
        pane = present(health.pane)
        require(
            matched is None or same_binding(matched, pane),
            "conflict",
            "Waited agent binding changed before final observation",
        )
        return {
            "teammate_id": current.teammate_id,
            "status": matched.status if matched is not None else "timeout",
            "wait_outcome": "matched" if matched is not None else "timeout",
            "runtime_status": pane.status,
            "runtime_health": health.status,
        }


def read(
    team: Team, reference: str, source: str, lines: int, ansi: bool
) -> dict[str, object]:
    with team.locked(reference) as record:
        record, health, _ = team.healthy(
            record,
            initial_snapshot=team.context.snapshot,
        )
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
        record, health, _ = team.healthy(
            record,
            initial_snapshot=team.context.snapshot,
        )
        team.runtime.focus(present(health.pane))
        return {"teammate_id": record.teammate_id, "focused": True}


def attach(team: Team, reference: str) -> int:
    with team.locked(reference) as record:
        _, health, _ = team.healthy(
            record,
            initial_snapshot=team.context.snapshot,
        )
        pane = present(health.pane)
    # Never retain a cooperative lock for an unbounded interactive terminal session.
    return team.runtime.attach(pane)
