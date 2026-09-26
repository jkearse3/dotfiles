"""The `read` tool, and the `replace` and `insert` edits the `edit` tool
applies, with the row rendering and line lookup the other tools share.

Rows are rendered as `<anchor>│<line>`. Edit results show each change's new
lines as `+` rows with current anchors, so the model can keep editing without
re-reading. Untouched lines keep their anchors and are not echoed, except for
the ` ` context rows around a removal, which show where the lines were.
"""

import re
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

from .anchors import AnchorStore, TrackedFile
from .checks import file_report
from .errors import ToolError

MAX_READ_LINES = 2000
# Keeps a full page under Claude Code's default 25k-token MCP result limit.
MAX_READ_CHARS = 60_000
MAX_LINE_CHARS = 2000
MAX_ECHOED_ROWS = 60
# Moved lines are known to the caller, so a move shows only its seams.
MOVE_ECHOED_ROWS = 4
MAX_CONTEXT_LINES = 3
STALE_CONTEXT_LINES = 3
# Characters an edit must restate from each endpoint line. Sixteen tells apart
# near-identical neighbors such as `def format_help(` and `def format_usage(`.
MIN_CHECK_CHARS = 16

# Separates a row's anchor from its line. U+2502 (box drawing) rather than an
# ASCII `|` or a tab: it almost never starts a line of code, so the boundary
# stays unambiguous next to Markdown tables, `||`, and tab indentation.
ANCHOR_DELIMITER = "│"
ANCHOR_REFERENCE = re.compile(r"\s*[+-]?\s*([a-z]{3,})(?:│.*)?", re.DOTALL)
COPIED_ROW_PREFIX = re.compile(r"^[+ ]?([a-z]{3,})│")
# The suffix `format_row` adds to a line cut at `MAX_LINE_CHARS`.
TRUNCATION_MARKER = re.compile(
    r"… \[line truncated from \d+ chars; replacing it replaces the whole line\]\s*$"
)


def read_file(
    store: AnchorStore, raw_path: str, offset: int = 1, limit: int = MAX_READ_LINES
) -> str:
    """Render lines `offset`..`offset+limit-1` (1-based) as anchored rows.

    A negative `offset` counts from the end, so `-5` shows the last five
    lines. Stops early at `MAX_READ_CHARS` and ends with a continuation hint
    whenever lines remain, or with the file report once the last line is
    shown, so the file's ending needs no separate check. Every rendered row
    becomes editable.
    """
    if offset == 0 or limit < 1:
        raise ToolError("E_BAD_REQUEST", "offset must not be 0 and limit must be at least 1")
    tracked = store.sync(resolve_path(raw_path))
    total = len(tracked.content.lines)
    if offset < 0:
        offset = max(1, total + offset + 1)
    if offset > total:
        raise ToolError(
            "E_BAD_REQUEST",
            f"offset {offset} is past the end of the file ({total} lines)",
        )

    start = offset - 1
    stop = min(total, start + min(limit, MAX_READ_LINES))
    rows: list[str] = []
    size = 0
    for index in range(start, stop):
        row = format_row(tracked, index)
        if len(rows) > 0 and size + len(row) > MAX_READ_CHARS:
            stop = index
            break
        tracked.served.add(tracked.anchors[index])
        rows.append(row)
        size += len(row) + 1

    if stop < total:
        rows.append(
            f"[Showing lines {offset}-{stop} of {total}. Use offset={stop + 1} to continue.]"
        )
    else:
        if offset > 1:
            rows.append(f"[Showing lines {offset}-{total} of {total}.]")
        rows.append(file_report(tracked))
    return "\n".join(rows)


@dataclass(frozen=True)
class PlannedEdit:
    """A checked edit of one tracked file, not yet written: `lines[start:stop]`
    becomes `new_lines`."""

    start: int
    stop: int
    new_lines: list[str]
    summary: str
    warnings: list[str]

    def is_noop(self, tracked: TrackedFile) -> bool:
        return tracked.content.lines[self.start : self.stop] == self.new_lines


def replace_lines(
    store: AnchorStore,
    raw_path: str,
    first: str | None,
    first_text: str,
    last: str | None,
    last_text: str,
    lines: object,
) -> str:
    """Replace the inclusive line range `first`..`last` with `lines`.

    Refuses as `plan_replace` describes.
    """
    tracked = store.sync(resolve_path(raw_path))
    edit = plan_replace(tracked, first, first_text, last, last_text, lines)
    if edit.is_noop(tracked):
        return "No change: the replacement matches the current lines."
    updated = store.commit(tracked, edit.start, edit.stop, edit.new_lines)
    return edit_result(
        updated, edit.summary, edit.start, len(edit.new_lines), edit.warnings
    )


def plan_replace(
    tracked: TrackedFile,
    first: str | None,
    first_text: str,
    last: str | None,
    last_text: str,
    lines: object,
) -> PlannedEdit:
    """Check a replacement of the inclusive line range `first`..`last`.

    `first_text` and `last_text` repeat the start of each endpoint line (see
    `check_line_text`), and find it alone when its anchor is None (see
    `locate_range`). Refuses with `E_STALE_ANCHOR` for an anchor that no
    longer exists, `E_CONTENT_MISMATCH` when an endpoint is not the line the
    caller described, the refusals of `find_line_by_text`, and
    `E_RANGE_UNSERVED` as `require_range_served` describes; each error carries
    fresh rows so the retry needs no `read`.
    """
    start, stop = locate_range(tracked, first, first_text, last, last_text)
    return plan_range_replace(tracked, start, stop, lines)


def plan_range_replace(
    tracked: TrackedFile, start: int, stop: int, lines: object
) -> PlannedEdit:
    """Check a replacement of the located line indexes `start`..`stop - 1`.

    Refuses with `E_RANGE_UNSERVED` as `require_range_served` describes, and
    with `E_BAD_REQUEST` for malformed `lines`.
    """
    require_range_served(tracked, start, stop)
    new_lines, warnings = normalize_lines(lines, tracked)

    if (
        len(new_lines) > 0
        and start > 0
        and repeats(new_lines[0], tracked.content.lines[start - 1])
    ):
        warnings.append(
            f"The first new line repeats line {start}, just above the range; check for a duplicate."
        )
    if (
        len(new_lines) > 0
        and stop < len(tracked.content.lines)
        and repeats(new_lines[-1], tracked.content.lines[stop])
    ):
        warnings.append(
            f"The last new line repeats line {stop + 1}, just below the range; check for a duplicate."
        )
    summary = f"Replaced lines {start + 1}-{stop} with {len(new_lines)} line(s)."
    return PlannedEdit(start, stop, new_lines, summary, warnings)


def insert_lines(
    store: AnchorStore,
    raw_path: str,
    anchor: str | None,
    anchor_text: str,
    position: str,
    lines: object,
) -> str:
    """Insert `lines` before or after the line named by `anchor`, which stays.

    Refuses as `plan_insert` describes.
    """
    tracked = store.sync(resolve_path(raw_path))
    edit = plan_insert(tracked, anchor, anchor_text, position, lines)
    if edit.is_noop(tracked):
        return "No change: no lines to insert."
    updated = store.commit(tracked, edit.start, edit.stop, edit.new_lines)
    return edit_result(
        updated, edit.summary, edit.start, len(edit.new_lines), edit.warnings
    )


def plan_insert(
    tracked: TrackedFile,
    anchor: str | None,
    anchor_text: str,
    position: str,
    lines: object,
) -> PlannedEdit:
    """Check an insertion before or after the line named by `anchor`.

    `anchor_text` repeats the start of the anchor line (see `check_line_text`),
    or finds it alone when `anchor` is None (see `locate_insertion`).
    """
    index = locate_insertion(tracked, anchor, anchor_text, position)
    return plan_insert_at(tracked, index, position, lines)


def plan_insert_at(
    tracked: TrackedFile, index: int, position: str, lines: object
) -> PlannedEdit:
    """Check an insertion `position` (`before` or `after`) the located line
    `index`. Refuses with `E_BAD_REQUEST` for malformed `lines`."""
    new_lines, warnings = normalize_lines(lines, tracked)
    start = stop = index if position == "before" else index + 1
    summary = f"Inserted {len(new_lines)} line(s) {position} line {index + 1}."
    if len(new_lines) == 0:
        return PlannedEdit(start, stop, new_lines, summary, warnings)

    anchor_line = tracked.content.lines[index]
    edge = new_lines[-1] if position == "before" else new_lines[0]
    if repeats(edge, anchor_line):
        warnings.append(
            "The inserted lines repeat the anchor line, which is kept; check for a duplicate."
        )
    if tracked.content.is_empty:
        # An empty file's one row is a placeholder, not a line to keep, so the
        # inserted lines replace it instead of leaving a blank line beside them.
        start, stop = 0, 1
    return PlannedEdit(start, stop, new_lines, summary, warnings)


def locate_range(
    tracked: TrackedFile,
    first: str | None,
    first_text: str,
    last: str | None,
    last_text: str,
) -> tuple[int, int]:
    """Return the line index range `[start, stop)` from `first` to `last`,
    in either order, after checking both endpoints' text.

    An endpoint whose anchor is None is found by its text alone: the first
    must start exactly one line of the file, and the last is the nearest line
    at or after the first endpoint that its text starts, so a range can be
    named by its opening and closing lines without a read.
    """
    if first is not None and last is not None:
        start = locate(tracked, parse_anchor(first, "first"), first_text)
        stop = locate(tracked, parse_anchor(last, "last"), last_text)
        check_line_text(tracked, start, first_text, "first_text")
        check_line_text(tracked, stop, last_text, "last_text")
        return min(start, stop), max(start, stop) + 1

    start = locate_line(tracked, first, first_text, "first_text")
    if last is None:
        stop = find_line_by_text(tracked, last_text, "last_text", start, unique=False)
    else:
        stop = locate(tracked, parse_anchor(last, "last"), last_text)
        check_line_text(tracked, stop, last_text, "last_text")
    return min(start, stop), max(start, stop) + 1


def locate_line(
    tracked: TrackedFile, anchor: str | None, text: str, field: str
) -> int:
    """Return the index of the line named by `anchor` and its restated `text`,
    or by `text` alone when `anchor` is None, which must start exactly one
    line. `field` names `text` in refusals."""
    if anchor is None:
        return find_line_by_text(tracked, text, field, 0, unique=True)
    index = locate(tracked, parse_anchor(anchor, field.removesuffix("_text")), text)
    check_line_text(tracked, index, text, field)
    return index


def locate_insertion(
    tracked: TrackedFile, anchor: str | None, anchor_text: str, position: str
) -> int:
    """Return the index of a served anchor line that an insertion or move
    targets, after checking its text and `position`. With no anchor, the
    line is the one line of the file that `anchor_text` starts."""
    if position not in ("before", "after"):
        raise ToolError("E_BAD_REQUEST", 'position must be "before" or "after"')
    if anchor is None:
        return find_line_by_text(tracked, anchor_text, "anchor_text", 0, unique=True)
    index = locate(tracked, parse_anchor(anchor, "anchor"), anchor_text)
    check_line_text(tracked, index, anchor_text, "anchor_text")
    require_served(tracked, index, index + 1)
    return index


def append_index(tracked: TrackedFile) -> int:
    """Return the index of the line that appended lines go after: the last
    non-blank line, so trailing blank lines stay at the end, or the last line
    when every line is blank."""
    lines = tracked.content.lines
    for index in range(len(lines) - 1, -1, -1):
        if lines[index].strip() != "":
            return index
    return len(lines) - 1


def find_line_by_text(
    tracked: TrackedFile, text: str, field: str, start: int, unique: bool
) -> int:
    """Return the first line at or after index `start` that `text` starts, as
    `check_line_text` matches it, and serve it, since the caller stated it.

    With `unique`, exactly one line of the file may match. Refuses with
    `E_TEXT_NOT_FOUND` when no line matches, and with `E_TEXT_AMBIGUOUS` and
    the matching rows, which become editable, when several do.
    """
    matching = [
        index
        for index in range(start, len(tracked.content.lines))
        if starts_line(tracked, index, text)
    ]
    if len(matching) == 0:
        where = "" if start == 0 else f" at or after line {start + 1}"
        raise ToolError(
            "E_TEXT_NOT_FOUND",
            f"No line{where} starts with `{field}` {text!r} (at least "
            + f"{MIN_CHECK_CHARS} characters, or the whole line). Give its anchor instead.",
        )
    if unique and len(matching) > 1:
        shown = matching[:MAX_ECHOED_ROWS]
        rows = "\n".join(render_row(tracked, index) for index in shown)
        more = (
            f"\n[{len(matching) - len(shown)} more matching row(s) not shown.]"
            if len(shown) < len(matching)
            else ""
        )
        raise ToolError(
            "E_TEXT_AMBIGUOUS",
            f"`{field}` {text!r} starts {len(matching)} lines. Retry with more of the "
            + f"line, or with the anchor of the one you mean:\n{rows}{more}",
        )

    index = matching[0]
    tracked.served.add(tracked.anchors[index])
    return index


def resolve_path(raw_path: str) -> Path:
    if raw_path == "" or "\0" in raw_path:
        raise ToolError("E_BAD_REQUEST", "path must be a non-empty path without NUL")
    path = Path(raw_path).expanduser()
    return (path if path.is_absolute() else Path.cwd() / path).resolve()


def display_path(path: Path) -> str:
    """`path` as results show it: relative to the working directory when
    inside it, which keeps rows short, otherwise absolute."""
    try:
        return str(path.relative_to(Path.cwd()))
    except ValueError:
        return str(path)


def parse_anchor(value: object, field: str) -> str:
    """Accept a bare anchor or a pasted row (`abc│...`, `+abc│...`)."""
    match = ANCHOR_REFERENCE.fullmatch(value) if isinstance(value, str) else None
    if match is None:
        raise ToolError(
            "E_BAD_REQUEST", f"{field} must be an anchor such as `abc`, got {value!r}"
        )
    return match.group(1)


def locate(tracked: TrackedFile, anchor: str, text: str) -> int:
    """Return the index of `anchor`'s line.

    `text` is the line's restated start. When the file has never had the
    anchor, usually a mis-copy, the refusal shows the served rows starting
    with `text` so the retry can take the right anchor.
    """
    index = tracked.positions.get(anchor)
    if index is not None:
        return index

    last_seen = tracked.retired.get(anchor)
    if last_seen is None:
        raise unknown_anchor_error(tracked, anchor, text)
    start = max(0, last_seen - STALE_CONTEXT_LINES)
    stop = min(len(tracked.anchors), last_seen + STALE_CONTEXT_LINES + 1)
    rows = "\n".join(render_row(tracked, index) for index in range(start, stop))
    raise ToolError(
        "E_STALE_ANCHOR",
        f"Anchor `{anchor}` no longer exists: its line was edited or changed on disk. "
        + f"Current rows near its last position:\n{rows}",
    )


def unknown_anchor_error(tracked: TrackedFile, anchor: str, text: str) -> ToolError:
    matching = [
        index
        for index, candidate in enumerate(tracked.anchors)
        if candidate in tracked.served and starts_line(tracked, index, text)
    ]
    message = f"Anchor `{anchor}` is unknown for {tracked.path}"
    if len(matching) == 0:
        return ToolError("E_STALE_ANCHOR", f"{message}; read the file to get its anchors.")

    shown = matching[:MAX_ECHOED_ROWS]
    rows = "\n".join(render_row(tracked, index) for index in shown)
    more = (
        f"\n[{len(matching) - len(shown)} more matching row(s) not shown.]"
        if len(shown) < len(matching)
        else ""
    )
    return ToolError(
        "E_STALE_ANCHOR",
        f"{message}. Shown rows starting with the given text:\n{rows}{more}\n"
        + "Retry with the anchor of the line you meant.",
    )


def check_line_text(
    tracked: TrackedFile, index: int, expected: str, field: str
) -> None:
    """Refuse unless `expected` is the start of line `index`.

    A copied anchor can belong to the wrong row, so edits restate each
    endpoint's content. Leading and trailing whitespace are ignored, and at
    least `MIN_CHECK_CHARS` characters (or the whole line, if shorter) must
    match. The text may also be the row as shown: a leading `anchor│` naming
    this line and a trailing truncation marker are dropped. Refuses with
    `E_CONTENT_MISMATCH` and the rows around the line.
    """
    if starts_line(tracked, index, expected):
        return

    start = max(0, index - STALE_CONTEXT_LINES)
    stop = min(len(tracked.anchors), index + STALE_CONTEXT_LINES + 1)
    rows = "\n".join(render_row(tracked, row) for row in range(start, stop))
    raise ToolError(
        "E_CONTENT_MISMATCH",
        f"`{field}` {expected!r} does not match the start of line {index + 1} "
        + f"(at least {MIN_CHECK_CHARS} characters, or the whole line if shorter). "
        + f"The anchor may be from the wrong row. Current rows:\n{rows}",
    )


def starts_line(tracked: TrackedFile, index: int, expected: str) -> bool:
    """Whether `expected` is the start of line `index`, as `check_line_text`
    describes."""
    actual = tracked.content.lines[index].strip()
    candidates = [expected]
    row = COPIED_ROW_PREFIX.match(expected.lstrip())
    if row is not None and row.group(1) == tracked.anchors[index]:
        candidates.append(expected.lstrip()[row.end() :])
    for candidate in candidates:
        given = TRUNCATION_MARKER.sub("", candidate).strip()
        if len(given) >= min(MIN_CHECK_CHARS, len(actual)) and actual.startswith(given):
            return True
    return False


def require_range_served(tracked: TrackedFile, start: int, stop: int) -> None:
    """Refuse an edit of lines `start`..`stop - 1` with `E_RANGE_UNSERVED`
    unless both endpoint lines are served and every line between them is
    served or has not changed on disk.

    The endpoints' text is already checked, so the range is the one the
    caller described, and deleting or moving a long range needs no read of
    its middle. A middle line that changed on disk is refused, because the
    caller may believe it still holds what it held before.
    """
    last = stop - 1
    if all(
        anchor in tracked.served
        or (index not in (start, last) and anchor not in tracked.changed_outside)
        for index, anchor in enumerate(tracked.anchors[start:stop], start=start)
    ):
        return
    raise unserved_range_error(tracked, start, stop)


def require_served(tracked: TrackedFile, start: int, stop: int) -> None:
    if all(anchor in tracked.served for anchor in tracked.anchors[start:stop]):
        return
    raise unserved_range_error(tracked, start, stop)


def unserved_range_error(tracked: TrackedFile, start: int, stop: int) -> ToolError:
    shown = min(stop, start + MAX_ECHOED_ROWS)
    rows = "\n".join(render_row(tracked, index) for index in range(start, shown))
    # The last row is always shown, so a range whose middle has not changed
    # on disk can be retried with its endpoints as they now are.
    more = ""
    if shown < stop - 1:
        more += f"\n[{stop - 1 - shown} more line(s) in the range; read offset={shown + 1} to see them.]"
    if shown < stop:
        more += "\n" + render_row(tracked, stop - 1)
    return ToolError(
        "E_RANGE_UNSERVED",
        f"The range includes lines you have not seen in their current form. Current rows:\n{rows}{more}\n"
        + "Retry with these anchors if the edit still applies.",
    )


def normalize_lines(value: object, tracked: TrackedFile) -> tuple[list[str], list[str]]:
    """Coerce the model's new lines into single lines without terminators.

    Accepts a list of strings or one string; embedded newlines split. Lines
    are written as given: when every non-blank line starts like a copied
    `anchor│` row of this file the result only warns, because the same shape
    can be ordinary content.
    """
    if isinstance(value, str):
        pieces = [value]
    elif isinstance(value, list) and all(isinstance(item, str) for item in value):
        pieces = [item for item in value if isinstance(item, str)]
    else:
        raise ToolError(
            "E_BAD_REQUEST", "lines must be an array of strings, one element per line"
        )
    lines = [line.removesuffix("\r") for piece in pieces for line in piece.split("\n")]
    for line in lines:
        if "\0" in line:
            raise ToolError("E_BAD_REQUEST", "lines must not contain NUL characters")
        try:
            _ = line.encode("utf-8")
        except UnicodeEncodeError:
            raise ToolError(
                "E_BAD_REQUEST", f"lines must be valid Unicode text: {line!r}"
            ) from None

    warnings: list[str] = []
    non_blank = [line for line in lines if line.strip() != ""]
    prefixes = [COPIED_ROW_PREFIX.match(line) for line in non_blank]
    known = tracked.positions.keys() | tracked.retired.keys()
    if len(non_blank) > 0 and all(
        match is not None and match.group(1) in known for match in prefixes
    ):
        warnings.append(
            "The new lines start with `anchor│` like copied rows and were written"
            + " as given; if that was not intended, replace them with content only."
        )
    return lines, warnings


def repeats(new_line: str, neighbor: str) -> bool:
    return len(new_line.strip()) > 1 and new_line == neighbor


def edit_result(
    tracked: TrackedFile, summary: str, start: int, count: int, warnings: list[str]
) -> str:
    """Summarize an applied edit with its new rows, or the context of a
    removal, and the file report."""
    rows = [f"{summary} {display_path(tracked.path)}", *hunk_rows(tracked, start, count)]
    rows += [f"Warning: {warning}" for warning in warnings]
    rows.append(file_report(tracked))
    return "\n".join(rows)


def hunk_rows(
    tracked: TrackedFile,
    start: int,
    count: int,
    header: str | None = None,
    echo_limit: int = MAX_ECHOED_ROWS,
    context: bool = False,
) -> list[str]:
    """Render the `count` new rows at `start` as `+` rows, serving them.

    More than `echo_limit` new rows show their head and tail only, each
    extended past blank rows so the first and last lines with content show,
    such as a moved range's first line behind its separator. A `count`
    of zero, or `context`, adds ` ` context rows around the change, extending past
    blank lines so it is anchored to visible content. With `header`, the rows
    are headed by `@<line>` for the first row shown, as in `grep` output, then
    `header`.
    """
    lines = tracked.content.lines
    before = start
    after = start + count
    if count == 0 or context:
        while before > 0 and start - before < MAX_CONTEXT_LINES:
            before -= 1
            if lines[before].strip() != "":
                break
        while after < len(lines) and after - (start + count) < MAX_CONTEXT_LINES:
            after += 1
            if lines[after - 1].strip() != "":
                break

    rows = [] if header is None else [f"@{before + 1}{header}"]
    rows += [" " + render_row(tracked, index) for index in range(before, start)]
    new = range(start, start + count)
    head = echo_limit // 2 + count_blank(lines, new)
    tail = echo_limit - echo_limit // 2 + count_blank(lines, reversed(new))
    if head + tail >= count:
        rows += [
            "+" + render_row(tracked, index) for index in range(start, start + count)
        ]
    else:
        hidden = count - head - tail
        rows += [
            "+" + render_row(tracked, index) for index in range(start, start + head)
        ]
        rows.append(
            f"[{hidden} new line(s) not shown; read offset={start + head + 1} limit={hidden} for their anchors.]"
        )
        rows += [
            "+" + render_row(tracked, index)
            for index in range(start + count - tail, start + count)
        ]
    rows += [" " + render_row(tracked, index) for index in range(start + count, after)]
    return rows


def count_blank(lines: list[str], indexes: Iterable[int]) -> int:
    """How many of `indexes`, in order, are blank lines before the first
    line with content."""
    blank = 0
    for index in indexes:
        if lines[index].strip() != "":
            break
        blank += 1
    return blank


def render_row(tracked: TrackedFile, index: int) -> str:
    """Render one row and mark its anchor as served."""
    tracked.served.add(tracked.anchors[index])
    return format_row(tracked, index)


def format_row(tracked: TrackedFile, index: int) -> str:
    anchor, line = tracked.row(index)
    if len(line) > MAX_LINE_CHARS:
        line = f"{line[:MAX_LINE_CHARS]}… [line truncated from {len(line)} chars; replacing it replaces the whole line]"
        # Keep in sync with `TRUNCATION_MARKER`.
    return f"{anchor}{ANCHOR_DELIMITER}{line}"
