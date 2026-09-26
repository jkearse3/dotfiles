"""Model Context Protocol server over stdio (newline-delimited JSON-RPC 2.0).

Implements only what a tool-calling client needs from a server: `initialize`,
`ping`, `tools/list`, and `tools/call`. One request is handled at a time, which
also serializes every file write this process makes.
"""

import io
import json
import sys
from collections.abc import Callable
from typing import IO, cast

from . import __version__
from .anchors import AnchorStore
from .batch import MAX_BATCH_EDITS, batch_edit
from .edit import expand_edits, parse_line_ref
from .errors import ToolError
from .grep import DEFAULT_MATCH_LIMIT, MAX_CONTEXT, GrepRequest, grep_files
from .move import move_lines
from .spacing import MAX_BLANK_LINES
from .substitute import SubstituteRequest, substitute_lines
from .tools import MAX_READ_LINES, read_file

SUPPORTED_PROTOCOL_VERSIONS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")

# Sent with every request a session makes, as are the tool descriptions below,
# so both stay as short as the tools' contracts allow.
INSTRUCTIONS = """\
Anchored editing for text files. `read` and `grep` show lines as `anchor│text` rows. Untouched lines keep their anchors, so edits chain without re-reading. Edit results end with a `File:` line (line endings, final newline, BOM), so no separate check is needed.

Prefer these tools to shell reads, searches, and edits for files you may edit. Put every known edit in one `edit` call, even across files; relocate lines with `move` and rename with `substitute`."""

LINES_SCHEMA: dict[str, object] = {
    "type": "array",
    "items": {"type": "string"},
    "description": 'One string per line, without anchors. [] deletes; [""] is one blank line.',
}

# Line and flag fields repeat across tools, so their full meaning is described
# once, in the `edit` description. A line field keeps a short reminder: without
# one, models send bare anchors or rows without their text.
LINE_SCHEMA: dict[str, object] = {
    "type": "string",
    "description": "A row as shown, text included (`abc│text`), or the text alone.",
}

FLAG_SCHEMA: dict[str, object] = {"type": "boolean", "const": True}

BLANK_LINES_SCHEMA: dict[str, object] = {"type": "integer", "minimum": 0, "maximum": MAX_BLANK_LINES}

TOOLS: list[dict[str, object]] = [
    {
        "name": "read",
        "description": f"Show a UTF-8 text file as `anchor│text` rows, up to {MAX_READ_LINES} lines per call. Reaching the last line adds the `File:` line.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "offset": {
                    "type": "integer",
                    "description": "1-based first line; negative counts from the end (-5: last five lines).",
                },
                "limit": {"type": "integer", "minimum": 1},
            },
            "required": ["path"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": True},
    },
    {
        "name": "edit",
        "description": "Apply edits. A line is named by its row as shown (`abc│text`) or by text starting only that line (16+ characters or the whole line). `{start, end?, lines}` replaces `start`..`end` (`end` defaults to `start`). `{after | before, lines}` inserts beside a line and `{append: true, blank_lines?, lines}` after the last non-blank line, `blank_lines` blank lines apart. Only range endpoints need to have been shown. An edit's `path` overrides the top-level one. Edits must not overlap; if any is refused, nothing is written.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "edits": {
                    "type": "array",
                    "minItems": 1,
                    "maxItems": MAX_BATCH_EDITS,
                    "items": {
                        "type": "object",
                        "properties": {
                            "path": {"type": "string"},
                            "start": LINE_SCHEMA,
                            "end": LINE_SCHEMA,
                            "after": LINE_SCHEMA,
                            "before": LINE_SCHEMA,
                            "append": FLAG_SCHEMA,
                            "blank_lines": BLANK_LINES_SCHEMA,
                            "lines": LINES_SCHEMA,
                        },
                        "required": ["lines"],
                        "additionalProperties": False,
                    },
                },
            },
            "required": ["edits"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": False},
    },
    {
        "name": "move",
        "description": "Move lines `start`..`end` `after` or `before` a line or, with `append: true`, to the end, in the same file or the existing file `to_path`. Blank lines separating the moved lines from their neighbors move with them; `blank_lines` instead sets exactly that many on each side and in the gap left. Neither file needs reading first.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "start": LINE_SCHEMA,
                "end": LINE_SCHEMA,
                "after": LINE_SCHEMA,
                "before": LINE_SCHEMA,
                "append": FLAG_SCHEMA,
                "blank_lines": BLANK_LINES_SCHEMA,
                "to_path": {"type": "string"},
            },
            "required": ["path", "start"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": False},
    },
    {
        "name": "substitute",
        "description": "Replace `pattern` on every matching line of a file, or of every file under a directory as `grep` lists them; every changed row comes back. `replacement` cannot add line breaks. `start`..`end`, named as in `edit`, limits a single file to a range.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "pattern": {"type": "string", "description": "Python regex, or text with `literal`."},
                "replacement": {"type": "string"},
                "literal": {"type": "boolean"},
                "ignore_case": {"type": "boolean"},
                "glob": {"type": "string"},
                "start": LINE_SCHEMA,
                "end": LINE_SCHEMA,
            },
            "required": ["path", "pattern", "replacement"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": False},
    },
    {
        "name": "grep",
        "description": f"Search with ripgrep, respecting ignore files and searching hidden files except .git and .jj; hits come back as editable `anchor│text` rows under each file path. Stops at `limit` matches (default {DEFAULT_MATCH_LIMIT}). With `count: true`, returns only matching-line counts per file.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "Rust regex, or text with `literal`."},
                "path": {"type": "string", "description": "File or directory; default the working directory."},
                "glob": {"type": "string"},
                "ignore_case": {"type": "boolean"},
                "literal": {"type": "boolean"},
                "context": {"type": "integer", "minimum": 0, "maximum": MAX_CONTEXT},
                "limit": {"type": "integer", "minimum": 1},
                "count": {"type": "boolean"},
            },
            "required": ["pattern"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": True},
    },
]

for tool in TOOLS:
    tool["_meta"] = {"anthropic/alwaysLoad": True}


def serve(source: IO[str], sink: IO[str], store: AnchorStore) -> None:
    """Answer JSON-RPC messages from `source` until it closes."""
    for line in source:
        if line.strip() == "":
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            send(
                sink,
                {
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {"code": -32700, "message": "Parse error"},
                },
            )
            continue
        if isinstance(message, dict):
            response = handle_message(cast(dict[str, object], message), store)
            if response is not None:
                send(sink, response)


def handle_message(
    message: dict[str, object], store: AnchorStore
) -> dict[str, object] | None:
    """Return the response for one message, or None for a notification."""
    if "id" not in message:
        return None
    request_id = message["id"]
    method = message.get("method")
    raw_params = message.get("params")
    params = cast(dict[str, object], raw_params) if isinstance(raw_params, dict) else {}

    if method == "initialize":
        requested = params.get("protocolVersion")
        version = (
            requested
            if isinstance(requested, str) and requested in SUPPORTED_PROTOCOL_VERSIONS
            else SUPPORTED_PROTOCOL_VERSIONS[0]
        )
        result: dict[str, object] = {
            "protocolVersion": version,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "hashline-mcp", "version": __version__},
            "instructions": INSTRUCTIONS,
        }
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": TOOLS}
    elif method == "tools/call":
        result = call_tool(params, store)
    else:
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {"code": -32601, "message": f"Unknown method {method}"},
        }
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def call_tool(params: dict[str, object], store: AnchorStore) -> dict[str, object]:
    """Run one tool; refusals become `isError` results the model can act on."""
    name = params.get("name")
    raw_arguments = params.get("arguments")
    arguments = (
        cast(dict[str, object], raw_arguments)
        if isinstance(raw_arguments, dict)
        else {}
    )
    handler = TOOL_HANDLERS.get(name) if isinstance(name, str) else None
    try:
        if handler is None:
            raise ToolError("E_BAD_REQUEST", f"Unknown tool {name}")
        text, is_error = handler(store, arguments), False
    except ToolError as error:
        text, is_error = str(error), True
    except OSError as error:
        text, is_error = f"[E_IO] {error}", True
    except Exception as error:
        # One malformed call must not end the server and its anchor state.
        text, is_error = f"[E_INTERNAL] {type(error).__name__}: {error}", True
    return {"content": [{"type": "text", "text": text}], "isError": is_error}


def run_read(store: AnchorStore, arguments: dict[str, object]) -> str:
    return read_file(
        store,
        string_argument(arguments, "path"),
        offset=integer_argument(arguments, "offset", 1),
        limit=integer_argument(arguments, "limit", MAX_READ_LINES),
    )


def run_edit(store: AnchorStore, arguments: dict[str, object]) -> str:
    return batch_edit(
        store,
        nullable_string_argument(arguments, "path"),
        expand_edits(arguments.get("edits")),
    )


def run_grep(store: AnchorStore, arguments: dict[str, object]) -> str:
    glob = arguments.get("glob")
    if glob is not None and not isinstance(glob, str):
        raise ToolError("E_BAD_REQUEST", "glob must be a string")
    request = GrepRequest(
        pattern=string_argument(arguments, "pattern"),
        path=optional_string_argument(arguments, "path", "."),
        glob=glob,
        ignore_case=boolean_argument(arguments, "ignore_case"),
        literal=boolean_argument(arguments, "literal"),
        context=integer_argument(arguments, "context", 0),
        limit=integer_argument(arguments, "limit", DEFAULT_MATCH_LIMIT),
        count=boolean_argument(arguments, "count"),
    )
    return grep_files(store, request)


def run_move(store: AnchorStore, arguments: dict[str, object]) -> str:
    # Refused rather than ignored: an unknown flag meant to widen the range
    # would otherwise leave `end` defaulting to `start` and move one line.
    unknown = sorted(arguments.keys() - tool_properties("move"))
    if len(unknown) > 0:
        raise ToolError("E_BAD_REQUEST", f"move does not take {', '.join(unknown)}")

    first, first_text = parse_line_ref(arguments.get("start"), "start")
    append = true_argument(arguments, "append")
    blank_lines = (
        integer_argument(arguments, "blank_lines", 0) if "blank_lines" in arguments else None
    )
    last, last_text = parse_line_ref(arguments.get("end", arguments.get("start")), "end")

    sides = [side for side in ("after", "before") if side in arguments]
    if len(sides) + int(append) != 1:
        raise ToolError("E_BAD_REQUEST", "give exactly one of after, before, or append")
    anchor, anchor_text, position = None, "", "after"
    if not append:
        position = sides[0]
        anchor, anchor_text = parse_line_ref(arguments[position], position)
    return move_lines(
        store,
        string_argument(arguments, "path"),
        first,
        first_text,
        last,
        last_text,
        anchor,
        anchor_text,
        position,
        nullable_string_argument(arguments, "to_path"),
        append=append,
        blank_lines=blank_lines,
    )


def run_substitute(store: AnchorStore, arguments: dict[str, object]) -> str:
    first = first_text = last = last_text = None
    if "start" in arguments or "end" in arguments:
        first, first_text = parse_line_ref(arguments.get("start"), "start")
        last, last_text = parse_line_ref(arguments.get("end", arguments.get("start")), "end")
    request = SubstituteRequest(
        path=string_argument(arguments, "path"),
        pattern=string_argument(arguments, "pattern"),
        replacement=string_argument(arguments, "replacement"),
        # Accepted from callers that count, though the schema leaves it out: a
        # miscount after a `grep` costs a retry turn more often than it catches
        # an unintended match, and every changed row comes back anyway.
        expected_count=(
            integer_argument(arguments, "expected_count", 0)
            if "expected_count" in arguments
            else None
        ),
        literal=boolean_argument(arguments, "literal"),
        ignore_case=boolean_argument(arguments, "ignore_case"),
        glob=nullable_string_argument(arguments, "glob"),
        first=first,
        first_text=first_text,
        last=last,
        last_text=last_text,
    )
    return substitute_lines(store, request)


TOOL_HANDLERS: dict[str, Callable[[AnchorStore, dict[str, object]], str]] = {
    "read": run_read,
    "edit": run_edit,
    "move": run_move,
    "substitute": run_substitute,
    "grep": run_grep,
}


def tool_properties(name: str) -> set[str]:
    """The argument names the listed schema of tool `name` declares."""
    tool = next(tool for tool in TOOLS if tool["name"] == name)
    schema = cast(dict[str, object], tool["inputSchema"])
    return set(cast(dict[str, object], schema["properties"]))


def string_argument(arguments: dict[str, object], name: str) -> str:
    value = arguments.get(name)
    if not isinstance(value, str):
        raise ToolError("E_BAD_REQUEST", f"{name} must be a string")
    return value


def nullable_string_argument(arguments: dict[str, object], name: str) -> str | None:
    return string_argument(arguments, name) if name in arguments else None


def optional_string_argument(
    arguments: dict[str, object], name: str, default: str
) -> str:
    return string_argument(arguments, name) if name in arguments else default


def boolean_argument(arguments: dict[str, object], name: str) -> bool:
    value = arguments.get(name, False)
    if not isinstance(value, bool):
        raise ToolError("E_BAD_REQUEST", f"{name} must be a boolean")
    return value


def true_argument(arguments: dict[str, object], name: str) -> bool:
    """Whether the flag `name`, which may only be given as true, is present."""
    if name not in arguments:
        return False
    if arguments[name] is not True:
        raise ToolError("E_BAD_REQUEST", f"{name} must be true when given")
    return True


def integer_argument(arguments: dict[str, object], name: str, default: int) -> int:
    value = arguments.get(name, default)
    if isinstance(value, bool) or not isinstance(value, int):
        raise ToolError("E_BAD_REQUEST", f"{name} must be an integer")
    return value


def send(sink: IO[str], message: dict[str, object]) -> None:
    _ = sink.write(json.dumps(message, ensure_ascii=False) + "\n")
    sink.flush()


def main() -> int:
    cast(io.TextIOWrapper, sys.stdin).reconfigure(encoding="utf-8")
    cast(io.TextIOWrapper, sys.stdout).reconfigure(encoding="utf-8")
    serve(sys.stdin, sys.stdout, AnchorStore())
    return 0
