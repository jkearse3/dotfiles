"""The `edit` tool's engine: several `replace` and `insert` edits in one call.

Every edit is checked against its file as it is before the call, exactly as
it would be checked alone, and nothing is written unless every edit passes.
Anchors stay valid across the batch, which is why edits can be planned
independently and applied together. Each file's edits land in one atomic
write; edits to several files are written file by file.
"""

from pathlib import Path
from typing import cast

from .anchors import AnchorStore, TrackedFile
from .checks import file_report
from .errors import ToolError
from .spacing import MAX_BLANK_LINES
from .text_file import fingerprint
from .tools import (
    PlannedEdit,
    append_index,
    display_path,
    hunk_rows,
    plan_insert,
    plan_insert_at,
    plan_replace,
    resolve_path,
)

MAX_BATCH_EDITS = 100

# One file's planned edits, each with its 1-based number in the batch.
FileEdits = tuple[TrackedFile, list[tuple[int, PlannedEdit]]]


def batch_edit(store: AnchorStore, raw_path: str | None, edits: object) -> str:
    """Apply `edits`, each a `replace` or `insert` edit given as an object with
    an `op` and that tool's fields, and optionally its own `path` overriding
    `raw_path`.

    Refuses with `E_BAD_REQUEST` for a malformed edit, an edit without a path,
    or edits to one file that overlap, and with any refusal of the edits' own
    tools, prefixed by the edit's number. Edits that change nothing are
    skipped. Files cannot change together atomically, so every file is checked
    for outside changes before the first write; a write that still fails
    after another file was written names the files already written.
    """
    if not isinstance(edits, list) or len(cast(list[object], edits)) == 0:
        raise ToolError("E_BAD_REQUEST", "edits must be a non-empty array")
    items = cast(list[object], edits)
    if len(items) > MAX_BATCH_EDITS:
        raise ToolError("E_BAD_REQUEST", f"a batch holds at most {MAX_BATCH_EDITS} edits")

    grouped: dict[Path, list[tuple[int, dict[str, object]]]] = {}
    for number, item in enumerate(items, start=1):
        path, fields = split_edit_path(item, raw_path, number)
        grouped.setdefault(path, []).append((number, fields))
    files = [plan_file(store.sync(path), entries) for path, entries in grouped.items()]

    changed = [(tracked, planned) for tracked, planned in files if len(planned) > 0]
    if len(changed) == 0:
        return "No change: every edit leaves the file as it is."
    written = write_files(store, changed)

    applied = sum(len(planned) for _, planned in written)
    skipped = len(items) - applied
    skipped_note = f", skipped {skipped} that changed nothing" if skipped > 0 else ""
    if len(grouped) == 1:
        updated, planned = written[0]
        rows = [f"Applied {applied} edit(s){skipped_note}. {display_path(updated.path)}"]
        return "\n".join([*rows, *result_rows(updated, planned), file_report(updated)])

    rows = [f"Applied {applied} edit(s) to {len(written)} file(s){skipped_note}."]
    for updated, planned in written:
        rows += [display_path(updated.path), *result_rows(updated, planned), file_report(updated)]
    return "\n".join(rows)


def split_edit_path(
    item: object, raw_path: str | None, number: int
) -> tuple[Path, dict[str, object]]:
    """Return an edit's file and its fields without `path`."""
    if not isinstance(item, dict):
        raise ToolError("E_BAD_REQUEST", f"Edit {number}: each edit must be an object")
    fields = dict(cast(dict[str, object], item))
    edit_path = fields.pop("path", raw_path)
    if edit_path is None:
        raise ToolError(
            "E_BAD_REQUEST", f"Edit {number}: give a path on the edit or the batch"
        )
    if not isinstance(edit_path, str):
        raise ToolError("E_BAD_REQUEST", f"Edit {number}: path must be a string")
    return resolve_path(edit_path), fields


def plan_file(
    tracked: TrackedFile, entries: list[tuple[int, dict[str, object]]]
) -> FileEdits:
    """Check one file's edits and return those that change something, in file
    order."""
    planned: list[tuple[int, PlannedEdit]] = []
    for number, fields in entries:
        try:
            edit = plan_edit(tracked, fields)
        except ToolError as error:
            raise ToolError(error.code, f"Edit {number}: {error.message}") from None
        planned.append((number, edit))

    # An insertion at the start of a replaced range goes before its new lines,
    # and edits at the same place keep their given order. Edits that change
    # nothing still count as overlapping, since they name conflicting lines.
    planned.sort(key=lambda entry: (entry[1].start, entry[1].stop, entry[0]))
    for (number, edit), (next_number, next_edit) in zip(planned, planned[1:]):
        if next_edit.start < edit.stop:
            raise ToolError(
                "E_BAD_REQUEST",
                f"Edits {number} and {next_number} overlap; merge them into one edit.",
            )
    return tracked, [(number, edit) for number, edit in planned if not edit.is_noop(tracked)]


def write_files(store: AnchorStore, files: list[FileEdits]) -> list[FileEdits]:
    """Write each file's edits and return the updated files with their edits."""
    for tracked, _ in files:
        if fingerprint(tracked.path) != tracked.version:
            raise ToolError(
                "E_FILE_CHANGED",
                f"{tracked.path} changed on disk during the edit; nothing was changed. Retry.",
            )

    written: list[FileEdits] = []
    for tracked, planned in files:
        splices = [(edit.start, edit.stop, edit.new_lines) for _, edit in planned]
        try:
            written.append((store.commit_splices(tracked, splices), planned))
        except ToolError as error:
            if len(written) == 0:
                raise
            raise partial_batch_error(written, error.code, error.message) from None
        except OSError as error:
            if len(written) == 0:
                raise
            raise partial_batch_error(written, "E_IO", str(error)) from None
    return written


def partial_batch_error(written: list[FileEdits], code: str, reason: str) -> ToolError:
    done = ", ".join(str(updated.path) for updated, _ in written)
    return ToolError(
        code,
        f"{reason.rstrip('.')}. These files were already edited: {done}. "
        + "Re-read the rest before retrying their edits.",
    )


def plan_edit(tracked: TrackedFile, fields: dict[str, object]) -> PlannedEdit:
    """Check one `op`-form edit. An insert edit with `append: true` in place
    of its anchor fields and `position` adds lines after the file's last
    non-blank line, preceded, with `blank_lines`, by exactly that many blank
    lines."""
    op = fields.get("op")
    append = fields.get("append") is True
    optional: set[str]
    if op == "replace":
        required = {"op", "first_text", "last_text", "lines"}
        optional = {"first", "last"}
    elif op == "insert" and append:
        required = {"op", "append", "lines"}
        optional = {"blank_lines"}
    elif op == "insert":
        required = {"op", "anchor_text", "position", "lines"}
        optional = {"anchor"}
    else:
        raise ToolError("E_BAD_REQUEST", 'op must be "replace" or "insert"')
    if not required <= fields.keys() <= required | optional:
        raise ToolError(
            "E_BAD_REQUEST",
            f"a {op} edit takes exactly the fields {', '.join(sorted(required))}, "
            + f"and optionally {', '.join(sorted(optional | {'path'}))}",
        )

    lines = fields["lines"]
    if append:
        if "blank_lines" in fields:
            lines = with_blank_lines(lines, fields["blank_lines"])
        return plan_insert_at(tracked, append_index(tracked), "after", lines)
    if op == "replace":
        return plan_replace(
            tracked,
            optional_string_field(fields, "first"),
            string_field(fields, "first_text"),
            optional_string_field(fields, "last"),
            string_field(fields, "last_text"),
            lines,
        )
    return plan_insert(
        tracked,
        optional_string_field(fields, "anchor"),
        string_field(fields, "anchor_text"),
        string_field(fields, "position"),
        lines,
    )


def with_blank_lines(lines: object, blank_lines: object) -> object:
    """`lines` without their leading blank lines, after exactly `blank_lines`
    blank lines. Refuses with `E_BAD_REQUEST` for a count outside
    0..`MAX_BLANK_LINES`; malformed `lines` pass through for
    `normalize_lines` to refuse."""
    if isinstance(blank_lines, bool) or not isinstance(blank_lines, int):
        raise ToolError("E_BAD_REQUEST", "blank_lines must be an integer")
    if not 0 <= blank_lines <= MAX_BLANK_LINES:
        raise ToolError("E_BAD_REQUEST", f"blank_lines must be 0-{MAX_BLANK_LINES}")
    if isinstance(lines, str):
        lines = lines.split("\n")
    if not isinstance(lines, list):
        return lines
    items = cast(list[object], lines)
    first = 0
    while first < len(items) and isinstance(items[first], str) and str(items[first]).strip() == "":
        first += 1
    return [*[""] * blank_lines, *items[first:]]


def optional_string_field(fields: dict[str, object], name: str) -> str | None:
    return string_field(fields, name) if name in fields else None


def string_field(fields: dict[str, object], name: str) -> str:
    value = fields[name]
    if not isinstance(value, str):
        raise ToolError("E_BAD_REQUEST", f"{name} must be a string")
    return value


def result_rows(
    tracked: TrackedFile, planned: list[tuple[int, PlannedEdit]]
) -> list[str]:
    """Render each applied edit's rows at its new position, headed by
    `@<line>`, with its warnings after all of them."""
    rows: list[str] = []
    warnings: list[str] = []
    shift = 0
    for number, edit in planned:
        start = edit.start + shift
        rows += hunk_rows(tracked, start, len(edit.new_lines), f" edit {number}")
        warnings += [f"Warning: edit {number}: {warning}" for warning in edit.warnings]
        shift += len(edit.new_lines) - (edit.stop - edit.start)
    return rows + warnings
