"""The `grep` tool: ripgrep search whose result rows are editable anchors.

Each hit is rendered like `read` output, so the edit tools can target
it without reading the file first. Files are grouped under their path, and each
run of consecutive lines starts with an `@<line>` marker.
"""

import json
import subprocess
import tempfile
import threading
from dataclasses import dataclass, replace
from pathlib import Path
from typing import cast

from .anchors import AnchorStore
from .errors import ToolError
from .tools import MAX_READ_CHARS, display_path, format_row, resolve_path

DEFAULT_MATCH_LIMIT = 100
# Counting renders no rows, so it may look at far more matches.
COUNT_MATCH_LIMIT = 100_000
MAX_CONTEXT = 10
RIPGREP_TIMEOUT_SECONDS = 30
LIMIT_REACHED = "limit"
TIMED_OUT = "timeout"
# Version control stores, hidden but never meant to be edited as text.
EXCLUDED_DIRECTORIES = (".git", ".jj")


@dataclass(frozen=True)
class GrepRequest:
    """One search. `context` counts lines on each side of a match; `limit`
    caps matched lines across all files. With `count`, only the number of
    matching lines per file is reported, and `limit` is ignored."""

    pattern: str
    path: str = "."
    glob: str | None = None
    ignore_case: bool = False
    literal: bool = False
    context: int = 0
    limit: int = DEFAULT_MATCH_LIMIT
    count: bool = False


def grep_files(store: AnchorStore, request: GrepRequest) -> str:
    """Search with ripgrep and render every hit as a served anchor row.

    Output stops within `MAX_READ_CHARS`, always showing at least one row, and
    ends with a note when rows were cut; only shown rows are served.

    Respects ignore files and searches hidden files except `.git` and `.jj`. Files that
    are not UTF-8 text are skipped. Raises `ToolError` with `E_BAD_REQUEST`
    for an invalid pattern or arguments and `E_GREP_FAILED` when ripgrep
    fails or times out.
    """
    if request.pattern == "":
        raise ToolError("E_BAD_REQUEST", "pattern must not be empty")
    if not 0 <= request.context <= MAX_CONTEXT:
        raise ToolError("E_BAD_REQUEST", f"context must be 0-{MAX_CONTEXT}")
    if request.limit < 1:
        raise ToolError("E_BAD_REQUEST", "limit must be at least 1")
    root = resolve_path(request.path)
    if not root.exists():
        raise ToolError("E_NOT_FOUND", f"{request.path} does not exist")

    if request.count:
        return count_matches(request, root)
    hits, stop_reason = run_ripgrep(request, root)
    if len(hits) == 0:
        return "No matches."

    sections: list[str] = []
    size = 0
    truncated = False
    for path, line_numbers in hits.items():
        section = render_section(
            store, path, line_numbers, MAX_READ_CHARS - size, len(sections) == 0
        )
        if section is None:
            continue
        if section.text != "":
            sections.append(section.text)
            size += len(section.text) + 1
        if not section.complete:
            truncated = True
            break

    if stop_reason == TIMED_OUT:
        sections.append(
            f"[Search timed out after {RIPGREP_TIMEOUT_SECONDS}s; results are partial.]"
        )
    if stop_reason == LIMIT_REACHED:
        sections.append(
            f"[Stopped at {request.limit} matches; narrow the pattern or path, "
            + "or give `count: true` for complete counts.]"
        )
    if truncated:
        sections.append("[Output cut at the size limit; narrow the pattern or path.]")
    return "\n".join(sections) if len(sections) > 0 else "No matches."


def count_matches(request: GrepRequest, root: Path) -> str:
    """Report how many lines match in each file and in total, serving no
    rows, for questions that need a number rather than lines to edit.
    Refuses with `E_BAD_REQUEST` when `context` is also given."""
    if request.context > 0:
        raise ToolError("E_BAD_REQUEST", "context does not apply when counting")
    hits, stop_reason = run_ripgrep(replace(request, limit=COUNT_MATCH_LIMIT), root)
    if len(hits) == 0:
        return "No matches."

    rows = [f"{display_path(path)}: {len(lines)}" for path, lines in hits.items()]
    total = sum(len(lines) for lines in hits.values())
    rows.append(f"Total: {total} matching line(s) in {len(hits)} file(s).")
    if stop_reason is not None:
        rows.append("[The search stopped early, so these counts are partial.]")
    return "\n".join(rows)


def run_ripgrep(
    request: GrepRequest, root: Path
) -> tuple[dict[Path, list[int]], str | None]:
    """Return matched and context line numbers per file, in ripgrep's order,
    and why the search stopped early: `LIMIT_REACHED`, `TIMED_OUT`, or None.

    ripgrep is killed at the match limit or after `RIPGREP_TIMEOUT_SECONDS`,
    so one search can never stall the server.
    """
    command = [
        "rg",
        "--json",
        "--hidden",
        *glob_arguments(request.glob),
        "--context",
        str(request.context),
    ]
    if request.ignore_case:
        command.append("--ignore-case")
    if request.literal:
        command.append("--fixed-strings")
    command += ["--regexp", request.pattern, "--", str(root)]

    hits: dict[Path, list[int]] = {}
    matches = 0
    last_match: tuple[str, int] | None = None
    stop_reason: str | None = None
    # A file rather than a pipe: permission errors across a large tree can
    # exceed a pipe buffer and block ripgrep while stdout is still being read.
    with tempfile.TemporaryFile() as errors:
        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=errors,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
        except FileNotFoundError:
            raise ToolError("E_GREP_FAILED", "ripgrep (rg) is not on PATH") from None

        expired = threading.Event()

        def expire() -> None:
            expired.set()
            process.kill()

        watchdog = threading.Timer(RIPGREP_TIMEOUT_SECONDS, expire)
        watchdog.start()
        with process:
            assert process.stdout is not None
            for line in process.stdout:
                try:
                    event = cast(dict[str, object], json.loads(line))
                except json.JSONDecodeError:
                    # A kill at the deadline can cut the last line short; keep
                    # what arrived before it.
                    if expired.is_set():
                        break
                    raise ToolError(
                        "E_GREP_FAILED", "ripgrep produced unreadable output"
                    ) from None
                kind = event.get("type")
                if kind not in ("match", "context"):
                    continue

                data = cast(dict[str, object], event["data"])
                path_field = cast(dict[str, object], data["path"])
                path_text = path_field.get("text")
                line_number = cast(int, data["line_number"])
                if matches >= request.limit and not is_trailing_context(
                    kind, path_text, line_number, last_match, request.context
                ):
                    # Past the limit, anything but the last kept match's
                    # after-context belongs to a match that is not shown.
                    stop_reason = LIMIT_REACHED
                    break
                if not isinstance(path_text, str):
                    continue  # A non-UTF-8 path cannot be edited through this server.

                hits.setdefault(Path(path_text).resolve(), []).append(line_number)
                if kind == "match":
                    matches += 1
                    last_match = (path_text, line_number)

            if stop_reason is not None:
                process.kill()
            _ = process.wait()
        watchdog.cancel()

        if expired.is_set() and stop_reason is None:
            stop_reason = TIMED_OUT
            if len(hits) == 0:
                raise ToolError(
                    "E_GREP_FAILED", "ripgrep timed out; narrow the pattern or path"
                )
        if stop_reason is None and process.returncode == 2 and len(hits) == 0:
            _ = errors.seek(0)
            message = errors.read(2000).decode("utf-8", "replace").strip()
            raise ToolError("E_BAD_REQUEST", f"ripgrep failed: {message}")
    return hits, stop_reason


def list_files(root: Path, glob: str | None) -> list[Path]:
    """Return the resolved files under `root` that a `grep` of it would search,
    in path order.

    Raises `ToolError` with `E_BAD_REQUEST` for an invalid glob and
    `E_GREP_FAILED` when ripgrep fails or takes over
    `RIPGREP_TIMEOUT_SECONDS`.
    """
    command = ["rg", "--files", "--sort", "path", "--hidden", *glob_arguments(glob)]
    command += ["--", str(root)]
    try:
        listed = subprocess.run(
            command,
            capture_output=True,
            timeout=RIPGREP_TIMEOUT_SECONDS,
            check=False,
        )
    except FileNotFoundError:
        raise ToolError("E_GREP_FAILED", "ripgrep (rg) is not on PATH") from None
    except subprocess.TimeoutExpired:
        raise ToolError(
            "E_GREP_FAILED", "listing files timed out; narrow the path or glob"
        ) from None
    # Exit status 1 means no files; 2 may only report unreadable entries.
    if listed.returncode == 2 and listed.stdout == b"":
        message = listed.stderr[:2000].decode("utf-8", "replace").strip()
        raise ToolError("E_BAD_REQUEST", f"ripgrep failed: {message}")

    # Keyed by inode so a file reached through two hard links is listed once:
    # rewriting it through one path would leave the other's state stale.
    files: dict[tuple[int, int], Path] = {}
    for raw in listed.stdout.splitlines():
        try:
            path = Path(raw.decode("utf-8")).resolve()
            metadata = path.stat()
        except UnicodeDecodeError:
            continue  # A non-UTF-8 path cannot be edited through this server.
        except OSError:
            continue
        _ = files.setdefault((metadata.st_dev, metadata.st_ino), path)
    return list(files.values())


def glob_arguments(glob: str | None) -> list[str]:
    """ripgrep flags for the caller's glob and the excluded VCS directories.

    The exclusions come last because a later glob overrides an earlier one:
    after them, a glob such as `*` cannot bring `.git` back into a search.
    """
    arguments: list[str] = ["--glob", glob] if glob is not None else []
    for directory in EXCLUDED_DIRECTORIES:
        arguments += ["--glob", f"!{directory}"]
    return arguments


def is_trailing_context(
    kind: object,
    path_text: object,
    line_number: int,
    last_match: tuple[str, int] | None,
    context: int,
) -> bool:
    """Whether an event is after-context of the last kept match.

    ripgrep emits a match's before-context ahead of the match itself, so once
    the limit is reached only these rows still belong to a shown match.
    """
    if kind != "context" or last_match is None:
        return False
    last_path, last_line = last_match
    return path_text == last_path and last_line < line_number <= last_line + context


@dataclass(frozen=True)
class RenderedSection:
    """One file's rendered hits, all of whose rows are served.

    `text` is empty when not even the first row fit, and `complete` is False
    when the budget cut any of the file's rows.
    """

    text: str
    complete: bool


def render_section(
    store: AnchorStore,
    path: Path,
    line_numbers: list[int],
    budget: int,
    force_first_row: bool,
) -> RenderedSection | None:
    """Render and serve as many of one file's hits as fit in `budget` characters.

    `force_first_row` shows the first row even past the budget, so a search
    whose first matching line is long still yields an editable row. Returns
    None, serving nothing, when the file is not editable text. Rows show the
    file's current content even if it changed after ripgrep read it.
    """
    try:
        tracked = store.sync(path)
    except (ToolError, OSError):
        return None

    total = len(tracked.content.lines)
    indexes = sorted({number - 1 for number in line_numbers if 0 < number <= total})
    header = display_path(path)
    rows: list[str] = []
    size = len(header)
    shown: list[int] = []
    previous = -2
    for index in indexes:
        lines = [format_row(tracked, index)]
        if index != previous + 1:
            lines.insert(0, f"@{index + 1}")
        cost = sum(len(line) + 1 for line in lines)
        if size + cost > budget and not (force_first_row and len(shown) == 0):
            break
        rows += lines
        size += cost
        shown.append(index)
        previous = index

    complete = len(shown) == len(indexes)
    if len(shown) == 0 and not complete:
        return RenderedSection(text="", complete=False)
    tracked.served.update(tracked.anchors[index] for index in shown)
    return RenderedSection(text="\n".join([header, *rows]), complete=complete)
