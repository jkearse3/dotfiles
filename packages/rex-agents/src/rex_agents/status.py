"""Read a helper's status from Rex, its result file, and watch's records."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import cast

from .rex import Rex, RexError
from .store import Helper, WatchRecord

REASON_LIMIT = 120


@dataclass(frozen=True)
class Status:
    """The one OSC 7501 status record that stands for a helper."""

    state: str
    updated_at: str | None
    reason: str | None


def derive_status(records: list[dict[str, object]]) -> Status | None:
    """Pick any `blocked` record, else the root record, else the first one."""
    chosen = next((r for r in records if r.get("state") == "blocked"), None)
    if chosen is None:
        chosen = next((r for r in records if r.get("id") is None), None)
    if chosen is None and len(records) > 0:
        chosen = records[0]
    if chosen is None:
        return None
    state = chosen.get("state")
    if not isinstance(state, str) or state == "":
        return None
    updated_at = chosen.get("updated_at")
    return Status(
        state=state,
        updated_at=updated_at if isinstance(updated_at, str) else None,
        reason=_reason(chosen.get("kind"), chosen.get("msg")),
    )


def _reason(kind: object, message: object) -> str | None:
    parts = [str(part) for part in (kind, message) if part is not None and part != ""]
    text = re.sub(r"\s+", " ", ": ".join(parts)).strip()
    return text[:REASON_LIMIT] if text != "" else None


def exit_reason(process: dict[str, object]) -> str | None:
    """Return `<code>` or `signal <name>` once the program ended, else None."""
    reply = process.get("last_exit")
    last_exit = cast(dict[str, object], reply) if isinstance(reply, dict) else {}
    if len(last_exit) == 0:
        return None
    code = last_exit.get("exit_code", -1)
    if isinstance(code, int) and code >= 0:
        return str(code)
    error = last_exit.get("error")
    signal = str(error) if error is not None and error != "" else "unknown"
    return f"signal {signal.removeprefix('signal: ')}"


def is_failure(exit: str) -> bool:
    """Whether an exit reason is a nonzero code or a signal, not 0 or `closed`."""
    return exit not in ("0", "closed")


def result_mtime(path: str) -> float | None:
    """Return the result file's modification time when it is non-empty."""
    try:
        stat = os.stat(path)
    except OSError:
        return None
    return stat.st_mtime if stat.st_size > 0 else None


def is_newer(updated_at: str | None, than: str | None) -> bool:
    """Whether Rex's UPDATED_AT is later than THAN."""
    if updated_at == than:
        return False
    new, old = parse_time(updated_at), parse_time(than)
    if new is None or old is None:
        return True
    return new > old


def parse_time(text: str | None) -> datetime | None:
    if text is None or text == "":
        return None
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else parsed.replace(tzinfo=timezone.utc)


@dataclass(frozen=True)
class HelperState:
    """A helper's state as `ls` shows it."""

    word: str
    reason: str | None
    since: str | None
    result_exists: bool
    block_open: bool

    @property
    def text(self) -> str:
        return f"{self.word} {self.reason}" if self.reason is not None else self.word


def helper_state(helper: Helper, record: WatchRecord, rex: Rex) -> HelperState:
    """Derive HELPER's state; the first match in the order below wins.

    Raises RexError when Rex fails for a reason other than a closed block.
    """
    mtime = result_mtime(helper.result)
    exists = mtime is not None

    def state(word: str, reason: str | None, since: str | None, open_: bool) -> HelperState:
        return HelperState(word, reason, since, exists, open_)

    if helper.released_at is not None:
        return state("released", None, iso_from_unix(helper.released_at), False)
    if record.exited is not None:
        open_ = record.exited != "closed" and _is_open(rex, helper.block)
        return state("exited", record.exited, iso_from_unix(record.exited_at), open_)

    try:
        exited = exit_reason(rex.process(helper.block))
        status = None if exited is not None else derive_status(rex.program_status(helper.block))
    except RexError as error:
        if not error.not_found:
            raise
        return state("exited", "closed", None, False)
    if exited is not None:
        return state("exited", exited, None, True)

    since = _iso_from_rex(status.updated_at) if status is not None else None
    if status is not None and status.state in ("working", "blocked"):
        reason = status.reason if status.state == "blocked" else None
        return state(status.state, reason, since, True)
    if status is not None and status.state == "error":
        return state("error", status.reason, since, True)
    if mtime is not None:
        return state("done", None, iso_from_unix(mtime), True)
    if status is not None and status.state == "done":
        return state("done", None, since, True)
    if record.done_at is not None:
        return state("done", None, iso_from_unix(record.done_at), True)
    if status is not None and status.state == "idle":
        return state("idle", None, since, True)
    return state("starting", None, iso_from_unix(helper.registered_at), True)


def _is_open(rex: Rex, block: str) -> bool:
    try:
        _ = rex.process(block)
    except RexError as error:
        if error.not_found:
            return False
        raise
    return True


def iso_from_unix(seconds: float | None) -> str | None:
    if seconds is None:
        return None
    return datetime.fromtimestamp(seconds, timezone.utc).isoformat(timespec="seconds")


def _iso_from_rex(text: str | None) -> str | None:
    parsed = parse_time(text)
    if parsed is None:
        return text
    return parsed.astimezone(timezone.utc).isoformat(timespec="seconds")
