"""`rex-agents watch`: print one line per change in the parent's helpers."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TextIO

from .clock import Clock
from .rex import Rex, RexError
from .status import (
    Status,
    derive_status,
    exit_reason,
    is_failure,
    is_newer,
    result_mtime,
)
from .store import Helper, Store, StoreError, WatchRecord, WatchRecords

POLL_SECONDS = 2
DEFAULT_TIMEOUT = 1440
DONE_MARK = "✓ "
FAILED_MARK = "✗ "


@dataclass
class Watch:
    store: Store
    rex: Rex
    clock: Clock
    out: TextIO

    def run(self, *, until_news: bool, timeout: int | None) -> int:
        parent = self.store.parent
        lock = self.store.try_lock()
        if lock is None:
            self._print(f"{parent} watch-already-running")
            return 0
        limit = DEFAULT_TIMEOUT if timeout is None else timeout
        started = self.clock.now()
        try:
            while True:
                try:
                    printed, live = self._check()
                except (RexError, StoreError) as error:
                    self._print(f"{parent} watch-failed {_one_line(str(error))}")
                    return 1
                if until_news and printed > 0:
                    return 0
                if live == 0:
                    # A helper registered while this run held the lock may not
                    # have been checked yet; releasing first means either this
                    # run sees it here or the registering parent's next watch
                    # can take the lock.
                    lock.release()
                    if self._has_live():
                        lock = self.store.try_lock()
                        if lock is not None:
                            continue
                    return 0
                if limit == 0:
                    return 0
                elapsed = self.clock.now() - started
                if elapsed >= limit:
                    self._print(f"{parent} watch-ended")
                    return 0
                self.clock.sleep(min(POLL_SECONDS, limit - elapsed))
        finally:
            if lock is not None:
                lock.release()

    def _has_live(self) -> bool:
        try:
            records = self.store.watch_records()
            return any(
                not h.released and records.peek(h.block).exited is None
                for h in self.store.helpers()
            )
        except StoreError:
            return False

    def _check(self) -> tuple[int, int]:
        """Check every live helper once; return lines printed and helpers live."""
        records = self.store.watch_records()
        printed = live = 0
        for helper in self.store.helpers():
            if helper.released:
                continue
            record = records.get(helper.block)
            if record.exited is not None:
                continue
            check = _HelperCheck(self, helper, record, records)
            is_live = check.run()
            printed += check.printed
            live += is_live
        return printed, live

    def _print(self, line: str) -> None:
        _ = self.out.write(line + "\n")
        self.out.flush()


class _HelperCheck:
    def __init__(
        self, watch: Watch, helper: Helper, record: WatchRecord, records: WatchRecords
    ) -> None:
        self.watch = watch
        self.helper = helper
        self.record = record
        self.records = records
        self.printed = 0

    def run(self) -> bool:
        """Print this helper's news; return whether it is still live."""
        helper, record, rex = self.helper, self.record, self.watch.rex
        now = self.watch.clock.now()
        mtime = result_mtime(helper.result)

        try:
            exited = exit_reason(rex.process(helper.block))
        except RexError as error:
            if not error.not_found:
                raise
            exited = "closed"
        if exited is not None:
            if self._released_meanwhile():
                return False
            if mtime is not None and not record.result_done:
                record.result_done = True
                record.done_at = now
                self._emit("done", label=None if exited == "closed" else DONE_MARK)
            record.exited, record.exited_at = exited, now
            failed = is_failure(exited) and mtime is None
            self._emit(f"exited {exited}", label=FAILED_MARK if failed else None)
            return False

        try:
            status = derive_status(rex.program_status(helper.block))
        except RexError as error:
            if not error.not_found:
                raise
            return True  # Closed after `process` answered; the next check says so.

        state = status.state if status is not None else None
        if status is not None and state in ("blocked", "error"):
            if record.status != state or record.reason != status.reason:
                self._set_status(status)
                self._emit(f"{state} {status.reason}" if status.reason is not None else state)

        if (
            mtime is not None
            and not record.result_done
            and state != "working"
            and now - mtime >= POLL_SECONDS
        ):
            record.result_done = True
            record.done_at = now
            self._emit("done", label=DONE_MARK)

        if status is not None and self._turn_ended(status) and mtime is None:
            record.done_at = now
            self._set_status(status)
            self._emit("done")

        if status is not None and not (
            state == "idle" and record.status in ("done", "error")
        ):  # An `idle` after a reported turn end keeps that end as the last status.
            if (state, status.updated_at, status.reason) != (
                record.status,
                record.updated_at,
                record.reason,
            ):
                self._set_status(status)
                self.watch.store.save_watch_records(self.records)
        return True

    def _turn_ended(self, status: Status) -> bool:
        last = self.record.status
        if status.state == "done":
            return last != "done"
        if status.state == "idle":
            if last in ("working", "blocked"):
                return True
            return last == "idle" and is_newer(status.updated_at, self.record.updated_at)
        return False

    def _set_status(self, status: Status) -> None:
        self.record.status = status.state
        self.record.updated_at = status.updated_at
        self.record.reason = status.reason

    def _released_meanwhile(self) -> bool:
        """Whether the parent released this helper after this check began."""
        return any(
            h.released for h in self.watch.store.helpers() if h.block == self.helper.block
        )

    def _emit(self, news: str, *, label: str | None = None) -> None:
        """Print a line, then record it, so a line that fails to print is retried."""
        self.watch._print(f"{self.helper.block} {self.helper.stem} {news}")
        self.printed += 1
        self.watch.store.save_watch_records(self.records)
        if label is not None:
            _mark_tab(self.watch.rex, self.helper.block, label)


def _mark_tab(rex: Rex, block: str, mark: str) -> None:
    """Prefix the label of BLOCK's tab with MARK; a failure changes nothing."""
    try:
        placement = rex.placement(block)
        tab = next(t for t in rex.tabs(placement.session) if t.window == placement.window)
        label = tab.label
        for existing in (DONE_MARK, FAILED_MARK):
            label = label.removeprefix(existing)
        rex.rename_tab(placement.session, placement.window, mark + label)
    except (RexError, StopIteration):
        pass


def _one_line(text: str) -> str:
    return " ".join(text.split())
