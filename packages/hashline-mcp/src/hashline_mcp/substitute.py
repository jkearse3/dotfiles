"""The `substitute` tool: one pattern replaced on every matching line of a file
or of every file under a directory.

A substitution may be guarded by its count: when the caller states how many
lines it expects to change, nothing is written unless exactly that many match.
Every changed row comes back either way. Matching is per line, and each
file's rewrite is one atomic write that keeps the line count, so lines
that do not change keep their anchors. A directory is searched as `grep`
searches it.
"""

import re
import time
from dataclasses import dataclass
from pathlib import Path

from .anchors import AnchorStore, TrackedFile
from .checks import file_report
from .errors import ToolError
from .grep import RIPGREP_TIMEOUT_SECONDS, list_files
from .text_file import fingerprint, load_text_file
from .tools import (
    MAX_ECHOED_ROWS,
    display_path,
    locate_range,
    render_row,
    resolve_path,
)


@dataclass(frozen=True)
class SubstituteRequest:
    """One substitution in one file or under one directory.

    `pattern` is a Python regular expression, or plain text when `literal`.
    `replacement` may refer to groups as `\\1` or `\\g<name>` unless `literal`.
    `expected_count`, when given, is the number of lines the pattern must
    match, across all files. `glob` limits a directory's files. `first_text` and
    `last_text` restate the start of the lines of an inclusive range that
    limits matching in a file, found as `replace` finds them: by `first` and
    `last` when given, otherwise by the text alone.
    """

    path: str
    pattern: str
    replacement: str
    expected_count: int | None = None
    literal: bool = False
    ignore_case: bool = False
    glob: str | None = None
    first: str | None = None
    first_text: str | None = None
    last: str | None = None
    last_text: str | None = None


# One file's matching line indexes, ascending.
Matches = tuple[TrackedFile, list[int]]


def substitute_lines(store: AnchorStore, request: SubstituteRequest) -> str:
    """Replace every occurrence of the pattern on each matching line.

    Refuses with `E_BAD_REQUEST` for an invalid pattern, replacement, glob,
    or range, or a result that would split a line; `E_COUNT_MISMATCH` when
    `expected_count` is given and the number of matching lines differs;
    `E_NO_MATCH` when nothing matches; and the anchor refusals of
    `replace` for the range. Refusals that concern matching lines carry their
    current rows, so the retry needs no `read`. Nothing is written on refusal.
    """
    if request.pattern == "":
        raise ToolError("E_BAD_REQUEST", "pattern must not be empty")
    if request.expected_count is not None and request.expected_count < 1:
        raise ToolError("E_BAD_REQUEST", "expected_count must be at least 1")
    matcher = compile_pattern(request)
    root = resolve_path(request.path)
    if root.is_dir():
        found = directory_matches(store, root, request, matcher)
        many = True
    else:
        found = file_matches(store, root, request, matcher)
        many = False

    count = sum(len(indexes) for _, indexes in found)
    if request.expected_count is not None and count != request.expected_count:
        raise ToolError(
            "E_COUNT_MISMATCH",
            f"The pattern matches {count} line(s), not the expected "
            + f"{request.expected_count}; nothing was changed."
            + matching_rows_note(found, many),
        )
    if count == 0:
        raise ToolError("E_NO_MATCH", "The pattern matches no line; nothing was changed.")

    rewrites: list[tuple[TrackedFile, dict[int, str]]] = []
    for tracked, indexes in found:
        changes: dict[int, str] = {}
        for index in indexes:
            line = tracked.content.lines[index]
            new_line = substitute_line(matcher, request, line)
            if new_line != line:
                changes[index] = new_line
        if len(changes) > 0:
            rewrites.append((tracked, changes))
    if len(rewrites) == 0:
        return "No change: the substitution leaves every matching line as it is."

    written = write_rewrites(store, rewrites)
    changed = sum(len(changes) for _, changes in written)
    if not many:
        updated, changes = written[0]
        summary = f"Substituted on {changed} line(s). {display_path(updated.path)}"
        rows = [summary, *anchored_rows(updated, sorted(changes), "+")]
        return "\n".join([*rows, file_report(updated)])

    rows = [f"Substituted on {changed} line(s) in {len(written)} file(s)."]
    budget = MAX_ECHOED_ROWS
    for updated, changes in written:
        rows.append(display_path(updated.path))
        rows += anchored_rows(updated, sorted(changes), "+", budget)
        rows.append(file_report(updated))
        budget = max(0, budget - len(changes))
    return "\n".join(rows)


def compile_pattern(request: SubstituteRequest) -> re.Pattern[str]:
    source = re.escape(request.pattern) if request.literal else request.pattern
    try:
        return re.compile(source, re.IGNORECASE if request.ignore_case else 0)
    except re.error as error:
        raise ToolError("E_BAD_REQUEST", f"invalid pattern: {error}") from None


def file_matches(
    store: AnchorStore, path: Path, request: SubstituteRequest, matcher: re.Pattern[str]
) -> list[Matches]:
    if request.glob is not None:
        raise ToolError("E_BAD_REQUEST", "glob applies only when path is a directory")
    tracked = store.sync(path)
    start, stop = substitution_scope(tracked, request)
    indexes = [
        index
        for index in range(start, stop)
        if matcher.search(tracked.content.lines[index]) is not None
    ]
    return [(tracked, indexes)]


def directory_matches(
    store: AnchorStore, root: Path, request: SubstituteRequest, matcher: re.Pattern[str]
) -> list[Matches]:
    """Return the matching lines of every file `grep` would search under
    `root`, skipping files that are not editable text.

    Refuses with `E_BAD_REQUEST` when the scan takes over
    `RIPGREP_TIMEOUT_SECONDS`, since a partial scan cannot vouch for the count.
    """
    bounds = (request.first, request.first_text, request.last, request.last_text)
    if any(bound is not None for bound in bounds):
        raise ToolError("E_BAD_REQUEST", "a range applies only when path is a file")
    deadline = time.monotonic() + RIPGREP_TIMEOUT_SECONDS
    found: list[Matches] = []
    for path in list_files(root, request.glob):
        if time.monotonic() > deadline:
            raise ToolError(
                "E_BAD_REQUEST",
                f"Scanning {root} took over {RIPGREP_TIMEOUT_SECONDS}s; narrow the path or glob.",
            )
        tracked = store.files.get(path)
        try:
            if tracked is None:
                # Files without a match stay untracked.
                content, _ = load_text_file(path)
                if not any(matcher.search(line) is not None for line in content.lines):
                    continue
            tracked = store.sync(path)
        except (ToolError, OSError):
            continue
        indexes = [
            index
            for index, line in enumerate(tracked.content.lines)
            if matcher.search(line) is not None
        ]
        if len(indexes) > 0:
            found.append((tracked, indexes))
    return found


def substitution_scope(
    tracked: TrackedFile, request: SubstituteRequest
) -> tuple[int, int]:
    """Return the line index range `[start, stop)` the pattern may match in."""
    bounds = (request.first, request.first_text, request.last, request.last_text)
    if all(bound is None for bound in bounds):
        return 0, len(tracked.content.lines)
    if request.first_text is None or request.last_text is None:
        raise ToolError(
            "E_BAD_REQUEST",
            "a range needs both of its lines",
        )

    return locate_range(
        tracked, request.first, request.first_text, request.last, request.last_text
    )


def substitute_line(
    matcher: re.Pattern[str], request: SubstituteRequest, line: str
) -> str:
    """Return `line` with every match replaced, refusing a result that is not
    a single line of valid text."""
    try:
        if request.literal:
            new_line = matcher.sub(lambda _: request.replacement, line)
        else:
            new_line = matcher.sub(request.replacement, line)
    except (re.error, IndexError) as error:
        raise ToolError("E_BAD_REQUEST", f"invalid replacement: {error}") from None

    if "\n" in new_line or new_line.endswith("\r"):
        raise ToolError(
            "E_BAD_REQUEST",
            "the replacement must not add line breaks; use edit to add lines",
        )
    if "\0" in new_line:
        raise ToolError("E_BAD_REQUEST", "the replacement must not contain NUL")
    try:
        _ = new_line.encode("utf-8")
    except UnicodeEncodeError:
        raise ToolError(
            "E_BAD_REQUEST", "the replacement must be valid Unicode text"
        ) from None
    return new_line


def write_rewrites(
    store: AnchorStore, rewrites: list[tuple[TrackedFile, dict[int, str]]]
) -> list[tuple[TrackedFile, dict[int, str]]]:
    """Write each file's changed lines and return the updated files.

    Files cannot change together atomically, so every file is checked for
    outside changes before the first write. A write that still fails, whether
    refused or failing with `OSError` (reported as `E_IO`), names the files
    already written; when it is the first write, its error propagates unchanged.
    """
    for tracked, _ in rewrites:
        if fingerprint(tracked.path) != tracked.version:
            raise ToolError(
                "E_FILE_CHANGED",
                f"{tracked.path} changed on disk during the edit; nothing was changed. Retry.",
            )
    written: list[tuple[TrackedFile, dict[int, str]]] = []
    for tracked, changes in rewrites:
        try:
            written.append((store.commit_rewrite(tracked, changes), changes))
        except ToolError as error:
            if len(written) == 0:
                raise
            raise partial_substitution_error(written, error.code, error.message) from None
        except OSError as error:
            if len(written) == 0:
                raise
            raise partial_substitution_error(written, "E_IO", str(error)) from None
    return written


def partial_substitution_error(
    written: list[tuple[TrackedFile, dict[int, str]]], code: str, reason: str
) -> ToolError:
    """The error for a substitution whose `written` files were rewritten before
    a later file's write failed."""
    done = ", ".join(str(updated.path) for updated, _ in written)
    return ToolError(
        code,
        f"{reason.rstrip('.')}. These files were already rewritten: {done}. "
        + "Retry the substitution for the rest.",
    )


def matching_rows_note(found: list[Matches], many: bool) -> str:
    if all(len(indexes) == 0 for _, indexes in found):
        return ""
    rows = ["\nMatching rows:"]
    budget = MAX_ECHOED_ROWS
    for tracked, indexes in found:
        if len(indexes) == 0:
            continue
        if many:
            rows.append(display_path(tracked.path))
        rows += anchored_rows(tracked, indexes, "", budget)
        budget = max(0, budget - len(indexes))
    return "\n".join(rows)


def anchored_rows(
    tracked: TrackedFile,
    indexes: list[int],
    marker: str,
    limit: int = MAX_ECHOED_ROWS,
) -> list[str]:
    """Render and serve the rows at `indexes` (ascending), with an `@<line>`
    marker before each run of consecutive lines as in `grep` output. Rows
    past `limit` are summarized instead of shown."""
    rows: list[str] = []
    previous = -2
    for index in indexes[:limit]:
        if index != previous + 1:
            rows.append(f"@{index + 1}")
        rows.append(marker + render_row(tracked, index))
        previous = index
    if len(indexes) > limit:
        rows.append(f"[{len(indexes) - limit} more line(s) not shown.]")
    return rows
