"""`start`, `resume`, `release`, and `ls`: the helper lifecycle outside `watch`."""

from __future__ import annotations

import json
from dataclasses import dataclass, replace
from pathlib import Path
from typing import TextIO

from .clock import Clock
from .harness import (
    resume_command,
    resume_task,
    result_path,
    start_command,
    start_task,
    stem_for,
)
from .rex import OpenedTab, Placement, Rex, RexError
from .status import helper_state
from .store import Helper, Registration, Store, StoreError

SCREEN_TAIL_LINES = 5

# A helper in one of these states is mid-task, so resuming it would kill it.
BUSY_STATES = ("starting", "working", "blocked")


class CommandError(Exception):
    """A failure reported on stderr with exit status 1."""


@dataclass
class Context:
    """What every subcommand acts with, for the parent pane in $REX_BLOCK."""

    parent: str
    store: Store
    rex: Rex
    clock: Clock
    tmpdir: Path
    out: TextIO


def start(ctx: Context, name: str, harness: str, task: str, directory: Path) -> None:
    now = int(ctx.clock.now())
    stem = stem_for(name, now)
    if not ctx.store.reserve_stem(stem):
        raise CommandError(f"{stem} is already taken; start the helper under another name")
    result = result_path(ctx.tmpdir, stem, now)
    command = start_command(harness, stem, start_task(task, result))
    _launch(ctx, Registration(stem, name, harness, "", str(directory), str(result), now), command)


def resume(ctx: Context, query: str, task: str) -> None:
    helper = _find(ctx, query, by_block=False)
    state = helper_state(helper, ctx.store.watch_records().peek(helper.block), ctx.rex)
    if state.word in BUSY_STATES:
        raise CommandError(f"{helper.stem} is {state.text}; resume it once it has stopped")
    _release(ctx, helper)
    now = int(ctx.clock.now())
    result = result_path(ctx.tmpdir, helper.stem, now)
    command = resume_command(
        helper.harness, helper.stem, resume_task(task, result, Path(helper.result))
    )
    registration = Registration(
        helper.stem, helper.name, helper.harness, "", helper.dir, str(result), now
    )
    _launch(ctx, registration, command)


def release(ctx: Context, query: str) -> None:
    _release(ctx, _find(ctx, query, by_block=True))


def ls(ctx: Context, as_json: bool) -> None:
    records = ctx.store.watch_records()
    rows = []
    for helper in ctx.store.helpers():
        state = helper_state(helper, records.peek(helper.block), ctx.rex)
        tail = None
        if not state.result_exists and state.block_open:
            tail = _screen_tail(ctx.rex, helper.block)
        rows.append((helper, state, tail))

    if as_json:
        json.dump(
            [
                {
                    "name": helper.stem,
                    "harness": helper.harness,
                    "block": helper.block,
                    "state": state.word,
                    "reason": state.reason,
                    "since": state.since,
                    "result": helper.result,
                    "result_exists": state.result_exists,
                    "screen_tail": tail,
                }
                for helper, state, tail in rows
            ],
            ctx.out,
            indent=2,
        )
        _ = ctx.out.write("\n")
        return
    for helper, state, tail in rows:
        written = "written" if state.result_exists else "not written"
        since = state.since if state.since is not None else "-"
        _ = ctx.out.write(
            f"{helper.stem}  {helper.harness}  {helper.block}  {state.text}"
            f"  since {since}  {helper.result} ({written})\n"
        )
        for line in tail if tail is not None else []:
            _ = ctx.out.write(f"    │ {line}\n")


def _launch(ctx: Context, pending: Registration, command: list[str]) -> None:
    """Open the helper's tab, register it, place it, and print its details.

    PENDING is the registration with an empty block, filled in once the tab opens.
    """
    Path(pending.result).parent.mkdir(parents=True, exist_ok=True)
    parent = ctx.rex.placement(ctx.parent)
    tab = ctx.rex.open_tab(parent.session, pending.stem, pending.dir, command)
    registration = replace(pending, block=tab.block)
    try:
        ctx.store.register(registration)
    except StoreError:
        try:
            ctx.rex.close_block(tab.block)
        except RexError:
            pass
        raise
    _place(ctx, parent, tab)
    json.dump(
        {
            "name": registration.stem,
            "harness": registration.harness,
            "block": registration.block,
            "dir": registration.dir,
            "result": registration.result,
        },
        ctx.out,
    )
    _ = ctx.out.write("\n")


def _place(ctx: Context, parent: Placement, tab: OpenedTab) -> None:
    """Move TAB after the last of the parent's tab and its open helpers' tabs.

    A failure leaves the tab where Rex put it.
    """
    try:
        anchors = {parent.window}
        for helper in ctx.store.helpers():
            if helper.released or helper.block == tab.block:
                continue
            try:
                anchors.add(ctx.rex.placement(helper.block).window)
            except RexError as error:
                if not error.not_found:
                    raise
        order = [t.window for t in ctx.rex.tabs(parent.session)]
        positions = [
            i for i, window in enumerate(order) if window in anchors and window != tab.window
        ]
        if len(positions) > 0:
            ctx.rex.move_tab_after(parent.session, tab.window, order[max(positions)])
    except (RexError, StoreError):
        pass


def _release(ctx: Context, helper: Helper) -> None:
    """Mark HELPER released, then close its block when still open."""
    if not helper.released:
        ctx.store.release(helper.block, ctx.clock.now())
    try:
        ctx.rex.close_block(helper.block)
    except RexError as error:
        if not error.not_found:
            raise


def _find(ctx: Context, query: str, *, by_block: bool) -> Helper:
    """Match a full stem's latest registration, a block, or a unique name."""
    helpers = ctx.store.helpers()
    by_stem = [h for h in helpers if h.stem == query]
    if len(by_stem) > 0:
        return by_stem[-1]
    if by_block:
        matches = [h for h in helpers if h.block == query]
        if len(matches) > 0:
            return matches[-1]
    by_name = [h for h in helpers if not h.released and h.name == query]
    if len(by_name) == 1:
        return by_name[0]
    stems = ", ".join(dict.fromkeys(h.stem for h in helpers)) if len(helpers) > 0 else "none"
    reason = "matches several helpers" if len(by_name) > 0 else "matches no helper"
    raise CommandError(f"'{query}' {reason}; this parent's helpers: {stems}")


def _screen_tail(rex: Rex, block: str) -> list[str] | None:
    try:
        screen = rex.screen(block)
    except RexError as error:
        if error.not_found:
            return None
        raise
    lines = [line.rstrip() for line in screen.splitlines() if line.strip() != ""]
    return lines[-SCREEN_TAIL_LINES:]
