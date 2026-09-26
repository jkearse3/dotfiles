"""The compact line references and edits the MCP tools accept.

A line reference is one string: the line's row as a tool showed it
(`abc│start of text`), which gives both its anchor and its restated text, or
that text alone, which finds the line by content. Edits written this way cost
about half the output tokens of separate anchor and text fields. This module
turns them into the anchor and text pairs the edit functions take.
"""

import re
from typing import cast

from .errors import ToolError

# A row as `read`, `grep`, and edit results show it, optionally with the `+` or
# space an edit result puts before its rows.
LINE_ROW = re.compile(r"^[+ ]?([a-z]{3,})│(.*)$", re.DOTALL)

LineRef = tuple[str | None, str]


def parse_line_ref(value: object, field: str) -> LineRef:
    """Split a line reference into its anchor, or None for text alone, and
    its text. Refuses with `E_BAD_REQUEST` when `value` is not a string."""
    if not isinstance(value, str):
        raise ToolError("E_BAD_REQUEST", f"{field} must be a string")
    row = LINE_ROW.match(value)
    if row is None:
        return None, value
    return row.group(1), row.group(2)


def expand_edits(edits: object) -> object:
    """Turn compact edits into the `op` form `batch_edit` checks.

    An edit is `{start, end?, lines}`, replacing `start`..`end` (`end`
    defaulting to `start`), `{after | before, lines}`, inserting beside a
    line, or `{append: true, lines}`, adding lines at the end of the file,
    each with an optional `path`. Refuses with `E_BAD_REQUEST`, naming the
    edit, for any other shape. Anything but a list is returned as it is, for
    `batch_edit` to refuse.
    """
    if not isinstance(edits, list):
        return edits
    return [expand_edit(item, number) for number, item in enumerate(cast(list[object], edits), 1)]


def expand_edit(item: object, number: int) -> object:
    if not isinstance(item, dict):
        return item
    fields = cast(dict[str, object], item)
    allowed = {"path", "start", "end", "after", "before", "append", "blank_lines", "lines"}
    targets = [name for name in ("start", "after", "before", "append") if name in fields]
    unknown = sorted(fields.keys() - allowed)
    if (
        len(unknown) > 0
        or len(targets) != 1
        or ("end" in fields and targets != ["start"])
        or fields.get("append", True) is not True
        or ("blank_lines" in fields and targets != ["append"])
    ):
        raise ToolError(
            "E_BAD_REQUEST",
            f"Edit {number}: give lines and exactly one of start (with optional end), "
            + "after, before, or append: true (with optional blank_lines), "
            + "and optionally path",
        )

    expanded: dict[str, object] = {"lines": fields.get("lines")}
    if "path" in fields:
        expanded["path"] = fields["path"]
    try:
        if targets == ["start"]:
            first, first_text = parse_line_ref(fields["start"], "start")
            expanded |= {"op": "replace", "first_text": first_text}
            expanded |= {"first": first} if first is not None else {}
            last, last_text = parse_line_ref(fields.get("end", fields["start"]), "end")
            expanded["last_text"] = last_text
            expanded |= {"last": last} if last is not None else {}
        elif targets == ["append"]:
            expanded |= {"op": "insert", "append": True}
            if "blank_lines" in fields:
                expanded["blank_lines"] = fields["blank_lines"]
        else:
            position = targets[0]
            anchor, anchor_text = parse_line_ref(fields[position], position)
            expanded |= {"op": "insert", "anchor_text": anchor_text, "position": position}
            expanded |= {"anchor": anchor} if anchor is not None else {}
    except ToolError as error:
        raise ToolError(error.code, f"Edit {number}: {error.message}") from None
    return expanded
