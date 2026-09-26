"""Exact blank-line spacing around moved lines, for moves given `blank_lines`.

A move carries a blank-line separator when that keeps both places spaced as
before (see `move.plan_move`), but a caller who needs particular spacing, such
as two blank lines between sections, would otherwise read both files first
to predict the result. With `blank_lines`, the moved lines get exactly that
many blank lines on each side that has content, and the gap they leave closes
to the same number.
"""

from .text_file import Layout

MAX_BLANK_LINES = 10


def space_range(
    layout: Layout, lines: list[str], start: int, stop: int, blank_lines: int
) -> tuple[Layout, int, int]:
    """Return `layout` with exactly `blank_lines` blank lines between the
    range `layout[start:stop]` and the content on either side, with the
    range's new start and stop.

    Blank entries at the range's own edges, such as a carried separator, are
    dropped first. A side at the start or end of the file keeps its blank
    lines as they are. `lines` resolves the layout's existing-line entries.
    """
    moved = layout[start:stop]
    while len(moved) > 0 and is_blank(moved[0], lines):
        _ = moved.pop(0)
    while len(moved) > 0 and is_blank(moved[-1], lines):
        _ = moved.pop()
    if len(moved) == 0:
        return layout, start, stop

    before, after = layout[:start], layout[stop:]
    run_start = len(before)
    while run_start > 0 and is_blank(before[run_start - 1], lines):
        run_start -= 1
    if run_start > 0:
        before = before[:run_start] + resize(before[run_start:], blank_lines)
    run_stop = 0
    while run_stop < len(after) and is_blank(after[run_stop], lines):
        run_stop += 1
    if run_stop < len(after):
        after = resize(after[:run_stop], blank_lines) + after[run_stop:]
    return [*before, *moved, *after], len(before), len(before) + len(moved)


def close_gap(layout: Layout, lines: list[str], position: int, blank_lines: int) -> Layout:
    """Return `layout` with the blank lines around `position`, where removed
    lines were, set to exactly `blank_lines`. At the start or end of the
    file, the gap instead keeps only the blank lines on the file's edge side,
    since those at the other side separated the removed lines."""
    run_start = position
    while run_start > 0 and is_blank(layout[run_start - 1], lines):
        run_start -= 1
    run_stop = position
    while run_stop < len(layout) and is_blank(layout[run_stop], lines):
        run_stop += 1
    if run_start == 0 and run_stop == len(layout):
        return layout
    if run_start == 0:
        return [*layout[:position], *layout[run_stop:]]
    if run_stop == len(layout):
        return [*layout[:run_start], *layout[position:]]
    return [*layout[:run_start], *resize(layout[run_start:run_stop], blank_lines), *layout[run_stop:]]


def resize(run: Layout, count: int) -> Layout:
    """`run` of blank entries cut or padded with new blank lines to `count`,
    reusing existing lines first so they keep their anchors."""
    return [*run[:count], *[""] * (count - len(run))]


def is_blank(entry: int | str, lines: list[str]) -> bool:
    text = lines[entry] if isinstance(entry, int) else entry
    return text.strip() == ""
