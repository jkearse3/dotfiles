"""The `move` tool: a range of lines relocated without retyping it.

The range and the target line are checked as `replace` and `insert` check
theirs. Within one file the move is one atomic write, and every moved line
keeps its anchor and terminator. A move to another file inserts the lines
there with fresh anchors, then removes them from the source. A blank-line
separator moves with the range when that keeps both places spaced as before
(see `plan_move`).
"""

from dataclasses import dataclass

from .anchors import AnchorStore, TrackedFile
from .checks import file_report
from .errors import ToolError
from .spacing import MAX_BLANK_LINES, close_gap, space_range
from .text_file import Layout, fingerprint
from .tools import (
    MOVE_ECHOED_ROWS,
    append_index,
    display_path,
    hunk_rows,
    locate_insertion,
    locate_range,
    require_range_served,
    resolve_path,
)


def move_lines(
    store: AnchorStore,
    raw_path: str,
    first: str | None,
    first_text: str,
    last: str | None,
    last_text: str,
    anchor: str | None,
    anchor_text: str,
    position: str,
    to_path: str | None = None,
    *,
    append: bool = False,
    blank_lines: int | None = None,
) -> str:
    """Move the inclusive line range `first`..`last` of `raw_path` before or
    after the line named by `anchor`, in `to_path` when given.

    With `append`, the lines go after the target's last non-blank line and
    `anchor`, `anchor_text`, and `position` are ignored; a range that already
    ends its file stays in place. Finds and refuses as
    `replace` does for the range and as `insert` does for the anchor, and
    refuses with `E_BAD_REQUEST` when the anchor lies inside the range. With
    `blank_lines`, the moved lines end up with exactly that many blank lines
    on each side that has content, and the gap they leave closes to the same
    number (see `spacing`); a count outside 0..`MAX_BLANK_LINES` is refused
    with `E_BAD_REQUEST`.
    """
    if blank_lines is not None and not 0 <= blank_lines <= MAX_BLANK_LINES:
        raise ToolError("E_BAD_REQUEST", f"blank_lines must be 0-{MAX_BLANK_LINES}")
    if append:
        anchor, position = None, "after"
    source = store.sync(resolve_path(raw_path))
    start, stop = locate_range(source, first, first_text, last, last_text)
    require_range_served(source, start, stop)
    target_path = resolve_path(to_path) if to_path is not None else source.path
    if target_path == source.path:
        index = target_index(source, anchor, anchor_text, position, append)
        if start <= index < stop:
            if not append:
                raise ToolError("E_BAD_REQUEST", "anchor names a line inside the moved range")
            # The range already ends the file, so appending leaves it in place;
            # anchoring before its first line keeps `blank_lines` spacing it.
            index, position = start, "before"
        return move_within(store, source, start, stop, index, position, blank_lines)
    if target_path.exists() and target_path.samefile(source.path):
        # A hard link: each path has its own anchors, and writing through one
        # would make the other's state stale mid-move.
        raise ToolError(
            "E_BAD_REQUEST", "to_path is a hard link to path; move within path instead"
        )
    target = store.sync(target_path)
    index = target_index(target, anchor, anchor_text, position, append)
    return move_across(store, source, start, stop, target, index, position, blank_lines)


def target_index(
    tracked: TrackedFile,
    anchor: str | None,
    anchor_text: str,
    position: str,
    append: bool,
) -> int:
    """The line the moved lines go beside: after the target's last non-blank
    line with `append`, otherwise the line `anchor` names."""
    if append:
        return append_index(tracked)
    return locate_insertion(tracked, anchor, anchor_text, position)


def move_within(
    store: AnchorStore,
    tracked: TrackedFile,
    start: int,
    stop: int,
    index: int,
    position: str,
    blank_lines: int | None,
) -> str:
    lines = tracked.content.lines
    plan = plan_move(lines, start, stop, lines, index, position, same_file=True)

    remaining = [
        line for line in range(len(lines)) if not plan.unit_start <= line < plan.unit_stop
    ]
    new_start = sum(1 for line in remaining if line < plan.destination)
    layout: Layout = [*remaining[:new_start], *plan.order, *remaining[new_start:]]
    new_stop = new_start + len(plan.order)
    kept_before = sum(1 for line in remaining if line < plan.unit_start)
    gap = kept_before + (len(plan.order) if new_start <= kept_before else 0)
    moved = [line for line in plan.order if lines[line].strip() != ""]
    if blank_lines is not None and len(moved) > 0:
        layout = close_gap(layout, lines, gap, blank_lines)
        first, last = layout.index(moved[0]), layout.index(moved[-1])
        layout, new_start, new_stop = space_range(layout, lines, first, last + 1, blank_lines)
        gap = gap_position(layout, lines, plan.unit_stop)
    if layout == list(range(len(lines))):
        return "No change: the lines are already there."
    updated = store.commit_layout(tracked, layout)

    rows = [
        f"Moved lines {start + 1}-{stop} {position} line {index + 1}; they keep their anchors."
        + spacing_note(plan, start, stop, blank_lines)
        + f" {display_path(updated.path)}",
        # The rows around the join show where the lines landed and how they
        # are spaced, which a caller would otherwise read the file to check.
        *hunk_rows(updated, new_start, new_stop - new_start, "", MOVE_ECHOED_ROWS, context=True),
        "Rows around where they were:",
        *hunk_rows(updated, gap, 0, ""),
        file_report(updated),
    ]
    return "\n".join(rows)


def move_across(
    store: AnchorStore,
    source: TrackedFile,
    start: int,
    stop: int,
    target: TrackedFile,
    index: int,
    position: str,
    blank_lines: int | None,
) -> str:
    if target.content.is_empty:
        # As in `insert`, the placeholder line of an empty file is replaced.
        plan = MovePlan(start, stop, list(range(start, stop)), 0)
        insert_start, insert_stop = 0, 1
    else:
        plan = plan_move(
            source.content.lines, start, stop, target.content.lines, index, position, same_file=False
        )
        insert_start = insert_stop = plan.destination
    moved = [source.content.lines[line] for line in plan.order]

    # Two files cannot change in one atomic write. Checking the source first
    # makes a failed removal after the insertion unlikely, and that order
    # leaves the lines in both files rather than in neither.
    if fingerprint(source.path) != source.version:
        raise ToolError(
            "E_FILE_CHANGED", f"{source.path} changed on disk during the edit; retry"
        )
    target_layout: Layout = [
        *range(insert_start),
        *moved,
        *range(insert_stop, len(target.content.lines)),
    ]
    source_layout: Layout = [
        line
        for line in range(len(source.content.lines))
        if not plan.unit_start <= line < plan.unit_stop
    ]
    moved_start, moved_end = insert_start, insert_start + len(moved)
    gap = plan.unit_start
    if blank_lines is not None:
        target_layout, moved_start, moved_end = space_range(
            target_layout, target.content.lines, moved_start, moved_end, blank_lines
        )
        source_layout = close_gap(source_layout, source.content.lines, gap, blank_lines)
        gap = gap_position(source_layout, source.content.lines, plan.unit_stop)

    updated_target = store.commit_layout(target, target_layout)
    try:
        updated_source = store.commit_layout(source, source_layout)
    except ToolError as error:
        raise partial_move_error(source, target, error.code, error.message) from None
    except OSError as error:
        raise partial_move_error(source, target, "E_IO", str(error)) from None

    rows = [
        f"Moved {len(moved)} line(s) from lines {plan.unit_start + 1}-{plan.unit_stop} of "
        + f"{display_path(source.path)} {position} line {index + 1} of {display_path(target.path)}."
        + spacing_note(plan, start, stop, blank_lines),
        display_path(updated_target.path),
        *hunk_rows(
            updated_target, moved_start, moved_end - moved_start, "", MOVE_ECHOED_ROWS, context=True
        ),
        file_report(updated_target),
        f"{display_path(updated_source.path)}, rows around where they were:",
        *hunk_rows(updated_source, gap, 0, ""),
        file_report(updated_source),
    ]
    return "\n".join(rows)


@dataclass(frozen=True)
class MovePlan:
    """Source lines `unit_start`..`unit_stop - 1`, the range and any blank-line
    separator carried with it, placed in `order` before target line
    `destination`, in the target's current numbering."""

    unit_start: int
    unit_stop: int
    order: list[int]
    destination: int


def plan_move(
    source_lines: list[str],
    start: int,
    stop: int,
    target_lines: list[str],
    index: int,
    position: str,
    same_file: bool,
) -> MovePlan:
    """Plan moving range `start`..`stop - 1` next to target line `index`.

    Sections of a file are usually separated by blank lines, and a move that
    left them behind would need follow-up edits to fix the spacing. When the
    range has a separator on each side, or on the one side that is not a
    file edge, and the destination sits beside a separator or a file edge,
    one separator travels with the range and lands on whichever side keeps
    both places spaced as before. Otherwise only the range moves.
    """
    only_range = MovePlan(
        start, stop, list(range(start, stop)), index if position == "before" else index + 1
    )
    unit = separator_unit(source_lines, start, stop)
    placement = separator_destination(target_lines, index, position)
    if unit is None or placement is None:
        return only_range

    unit_start, unit_stop = unit
    destination, separator_first = placement
    if same_file and unit_start < destination < unit_stop:
        return only_range
    moved = list(range(start, stop))
    separator = [line for line in range(unit_start, unit_stop) if not start <= line < stop]
    order = separator + moved if separator_first else moved + separator
    return MovePlan(unit_start, unit_stop, order, destination)


def separator_unit(lines: list[str], start: int, stop: int) -> tuple[int, int] | None:
    """The range plus the blank-line separator to carry with it, or None
    when the range has none or starts or ends with a blank line itself."""
    if is_blank(lines[start]) or is_blank(lines[stop - 1]):
        return None
    before = 0
    while start - before > 0 and is_blank(lines[start - before - 1]):
        before += 1
    after = 0
    while stop + after < len(lines) and is_blank(lines[stop + after]):
        after += 1

    if after > 0 and (before > 0 or start == 0):
        return start, stop + after
    if before > 0 and stop == len(lines):
        return start - before, stop
    return None


def separator_destination(
    lines: list[str], index: int, position: str
) -> tuple[int, bool] | None:
    """Where a range with a separator goes beside line `index`, and whether
    the separator comes first, or None when the line is blank or no
    separator or file edge borders the destination."""
    if is_blank(lines[index]):
        return None
    if position == "before":
        if index == 0 or is_blank(lines[index - 1]):
            return index, False
        return None

    after = index + 1
    while after < len(lines) and is_blank(lines[after]):
        after += 1
    if after == len(lines):
        return index + 1, True
    if after > index + 1:
        return after, False
    return None


def is_blank(line: str) -> bool:
    return line.strip() == ""


def spacing_note(plan: MovePlan, start: int, stop: int, blank_lines: int | None) -> str:
    if blank_lines is not None:
        return f" Spaced with {blank_lines} blank line(s) where they landed and where they were."
    carried = len(plan.order) - (stop - start)
    if carried == 0:
        return ""
    return f" {carried} blank separator line(s) moved with them."


def gap_position(layout: Layout, lines: list[str], unit_stop: int) -> int:
    """Where the gap left by moved lines ending before line `unit_stop` now
    is: the position of the first non-blank line that followed them, or the
    end of the file."""
    for line in range(unit_stop, len(lines)):
        if lines[line].strip() != "" and line in layout:
            return layout.index(line)
    return len(layout)


def partial_move_error(
    source: TrackedFile, target: TrackedFile, code: str, reason: str
) -> ToolError:
    """The error for a move whose lines reached `target` but stayed in `source`."""
    return ToolError(
        code,
        f"The lines were inserted into {target.path}, but removing them from "
        + f"{source.path} failed: {reason.rstrip('.')}. Remove them from "
        + f"{source.path} to finish the move.",
    )
