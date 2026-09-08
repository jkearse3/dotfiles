"""One cooperative request/result slot. Bodies never travel through command arguments."""

import time
from typing import BinaryIO

from .errors import TeamError, present, require
from .herdr import same_binding
from .models import MAX_REPLY_BYTES, SETTLED, Request
from .registry import Registry
from .teammates import Team


def read_body(stream: BinaryIO) -> str:
    body = stream.read(MAX_REPLY_BYTES + 1)
    require(len(body) <= MAX_REPLY_BYTES, "reply_size", "Reply exceeds 256 KiB")
    try:
        return body.decode("utf-8")
    except UnicodeError as error:
        raise TeamError("reply_encoding", "Reply must be valid UTF-8") from error


def result_view(request: Request) -> dict[str, object]:
    return {
        "request_id": request.request_id,
        "teammate_id": request.teammate_id,
        "delivery": request.delivery,
        "request_status": "completed" if request.reply is not None else "pending",
        "attribution": "cooperative_unverified",
        "content": request.reply,
        "created_at": request.created_at,
        "replied_at": request.replied_at,
    }


def request_view(
    request: Request,
    wait_outcome: str,
    *,
    runtime_status: str | None = None,
    runtime_health: str | None = None,
) -> dict[str, object]:
    return {
        **result_view(request),
        "wait_outcome": wait_outcome,
        "runtime_status": runtime_status,
        "runtime_health": runtime_health,
    }


def result(registry: Registry, request_id: str, wait: bool, timeout: int) -> Request:
    deadline = time.monotonic() + timeout
    while True:
        request = registry.request(request_id)
        if request.reply is not None or not wait or time.monotonic() >= deadline:
            return request
        time.sleep(min(0.1, max(0, deadline - time.monotonic())))


def request(
    team: Team, reference: str, text: str, wait: bool, timeout: int, allow_focused: bool
) -> dict[str, object]:
    require(
        bool(text) and "\0" not in text,
        "invalid_prompt",
        "Prompt must be nonempty text without NUL",
    )
    with team.locked(reference) as record:
        record, health, snapshot = team.healthy(record, settled=True)
        pane = present(health.pane)
        require(
            allow_focused
            or not pane.focused
            and snapshot.focused_tab_id != record.tab_id,
            "focused",
            "Focused teammate requires --allow-focused and a clear composer",
        )
        request_record = team.registry.prepare(record)
        augmented = text + (
            "\n\nWhen finished, submit your final response through:\n"
            f"pi-shepherd reply {request_record.request_id} --stdin\n"
            "Supply the response through standard input, not a command argument. "
            "Do not delegate further unless the human explicitly authorized it in your conversation."
        )
        try:
            team.runtime.prompt(pane, augmented)
        except TeamError as error:
            if error.uncertain:
                team.registry.delivered(request_record.request_id, True)
                uncertain = team.registry.request(request_record.request_id)
                return (
                    request_view(uncertain, "delivery_uncertain")
                    if wait
                    else result_view(uncertain)
                )
            # An unexpectedly early reply wins over cleanup even after definite rejection.
            current = team.registry.request(request_record.request_id)
            if current.reply is None:
                team.registry.cancel(request_record.request_id)
            raise
        team.registry.delivered(request_record.request_id, False)
    if not wait:
        return result_view(team.registry.request(request_record.request_id))
    return wait_request(team, request_record.request_id, timeout)


def wait_request(team: Team, request_id: str, timeout: int) -> dict[str, object]:
    start = time.monotonic()
    deadline = start + timeout
    saw_working = False
    while True:
        request_record = team.registry.request(request_id)
        if request_record.reply is not None:
            return request_view(request_record, "completed")
        if request_record.delivery != "submitted":
            return request_view(request_record, "delivery_uncertain")
        with team.locked(request_record.teammate_id) as record:
            _, health, _ = team.observe(record)
        # Recheck after observation: a final reply can race a settled status.
        request_record = team.registry.request(request_id)
        if request_record.reply is not None:
            return request_view(request_record, "completed")
        runtime_status = health.pane.status if health.pane is not None else "unknown"
        if health.status != "healthy" or runtime_status == "blocked":
            return request_view(
                request_record,
                (
                    "runtime_blocked"
                    if runtime_status == "blocked"
                    else "runtime_unhealthy"
                ),
                runtime_status=runtime_status,
                runtime_health=health.status,
            )
        saw_working = saw_working or runtime_status == "working"
        # Allow the initial terminal submission to leave its pre-prompt settled state.
        # This is an observation, never turn attribution or evidence of semantic success.
        if runtime_status in SETTLED and (saw_working or time.monotonic() - start >= 5):
            return request_view(
                request_record,
                "reply_missing",
                runtime_status=runtime_status,
                runtime_health=health.status,
            )
        if time.monotonic() >= deadline:
            return request_view(
                request_record,
                "timeout",
                runtime_status=runtime_status,
                runtime_health=health.status,
            )
        time.sleep(min(0.1, max(0, deadline - time.monotonic())))


def reply(team: Team, request_id: str, body: str) -> dict[str, object]:
    request = team.registry.request(request_id)
    identity = team.runtime.environment.get("PI_SHEPHERD_TEAMMATE_ID")
    require(
        identity == request.teammate_id,
        "reply_identity",
        "Caller is not the request's teammate",
    )
    with team.locked(request.teammate_id) as record:
        record, health, snapshot = team.healthy(record)
        current = team.runtime.current()
        caller = [
            agent
            for agent in snapshot.agents
            if agent.terminal_id == current.terminal_id
        ]
        require(
            len(caller) == 1
            and health.pane is not None
            and same_binding(caller[0], health.pane)
            and (current.pane_id, current.tab_id, current.workspace_id, current.kind)
            == (
                health.pane.pane_id,
                health.pane.tab_id,
                health.pane.workspace_id,
                health.pane.kind,
            ),
            "reply_identity",
            "Caller is not in the expected managed agent binding",
        )
        team.registry.reply(request_id, record.teammate_id, body)
    return {
        "request_id": request_id,
        "stored": True,
        "attribution": "cooperative_unverified",
    }
