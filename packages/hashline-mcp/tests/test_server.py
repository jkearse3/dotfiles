"""JSON-RPC framing and MCP method contracts over in-memory streams."""

import io
import json
import tempfile
import unittest
from pathlib import Path
from typing import cast
from unittest import mock

from hashline_mcp.anchors import AnchorStore
from hashline_mcp import server
from hashline_mcp.server import serve


def dig(value: object, *path: str | int) -> object:
    """Walk decoded JSON by keys and indexes, failing on a missing step."""
    for step in path:
        if isinstance(step, int) and isinstance(value, list):
            value = cast(list[object], value)[step]
        elif isinstance(step, str) and isinstance(value, dict):
            value = cast(dict[str, object], value)[step]
        else:
            raise AssertionError(f"Cannot follow {step!r} into {value!r}")
    return value


def exchange(*messages: object) -> list[object]:
    source = io.StringIO(
        "".join(json.dumps(message) + "\n" for message in messages) + "not json\n"
    )
    sink = io.StringIO()
    serve(source, sink, AnchorStore())
    return [json.loads(line) for line in sink.getvalue().splitlines()]


def tool_call(request_id: int, name: str, arguments: dict[str, object]) -> object:
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": "tools/call",
        "params": {"name": name, "arguments": arguments},
    }


class ServerTests(unittest.TestCase):
    def test_handshake_lists_always_loaded_tools(self) -> None:
        responses = exchange(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {"protocolVersion": "2025-06-18"},
            },
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 3, "method": "resources/list"},
        )

        initialize, tools, unknown, parse_error = responses
        self.assertEqual(dig(initialize, "result", "protocolVersion"), "2025-06-18")
        self.assertIsInstance(dig(initialize, "result", "instructions"), str)
        listed = cast(list[object], dig(tools, "result", "tools"))
        self.assertEqual(
            [dig(tool, "name") for tool in listed],
            ["read", "edit", "move", "substitute", "grep"],
        )
        self.assertTrue(
            all(dig(tool, "_meta", "anthropic/alwaysLoad") is True for tool in listed)
        )
        self.assertEqual(dig(unknown, "error", "code"), -32601)
        self.assertEqual(dig(parse_error, "error", "code"), -32700)

    def test_tool_call_success_and_refusal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "a.txt"
            _ = path.write_text("a\n")

            success, refusal = exchange(
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "tools/call",
                    "params": {"name": "read", "arguments": {"path": str(path)}},
                },
                {
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "tools/call",
                    "params": {"name": "edit", "arguments": {"path": str(path)}},
                },
            )[:2]

        self.assertIs(dig(success, "result", "isError"), False)
        self.assertRegex(
            str(dig(success, "result", "content", 0, "text")),
            r"^[a-z]{3}│a\nFile: LF line endings, final newline\.$",
        )
        self.assertIs(dig(refusal, "result", "isError"), True)
        self.assertIn(
            "[E_BAD_REQUEST]", str(dig(refusal, "result", "content", 0, "text"))
        )

    def test_substitute_call_parses_optional_arguments(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "a.txt"
            _ = path.write_text("A.b\n")

            substituted = exchange(
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "tools/call",
                    "params": {"name": "read", "arguments": {"path": str(path)}},
                },
                {
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "tools/call",
                    "params": {
                        "name": "substitute",
                        "arguments": {
                            "path": str(path),
                            "pattern": "a.b",
                            "replacement": "c",
                            "expected_count": 1,
                            "literal": True,
                            "ignore_case": True,
                        },
                    },
                },
            )[1]
            content = path.read_text()

        self.assertIs(dig(substituted, "result", "isError"), False)
        self.assertEqual(content, "c\n")

    def test_compact_edit_and_move_calls(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "a.py"
            _ = path.write_text("def a():\n    pass\n\n\ndef b():\n    pass\n")

            read, edited, moved = exchange(
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "tools/call",
                    "params": {"name": "read", "arguments": {"path": str(path)}},
                },
                {
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "tools/call",
                    "params": {
                        "name": "edit",
                        "arguments": {
                            "path": str(path),
                            "edits": [
                                {"start": "def a():", "lines": ["def first():"]},
                                {"after": "def b():", "lines": ["    x = 1"]},
                            ],
                        },
                    },
                },
                {
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "tools/call",
                    "params": {
                        "name": "move",
                        "arguments": {
                            "path": str(path),
                            "start": "def b():",
                            "end": "    pass",
                            "before": "def first():",
                        },
                    },
                },
            )[:3]
            content = path.read_text()

        rows = str(dig(read, "result", "content", 0, "text")).splitlines()
        self.assertEqual(len(rows), 7)
        self.assertTrue(rows[-1].startswith("File: "))
        self.assertIs(dig(edited, "result", "isError"), False)
        self.assertIs(dig(moved, "result", "isError"), False)
        self.assertEqual(content, "def b():\n    x = 1\n    pass\n\n\ndef first():\n    pass\n")

    def test_range_append_and_uncounted_substitute_calls(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "a.py"
            other = Path(directory) / "b.py"
            _ = path.write_text("def a():\n    one()\n    two()\n\n\ndef b():\n    pass\n")
            _ = other.write_text("import os\n")

            responses = exchange(
                tool_call(
                    1,
                    "edit",
                    {
                        "path": str(path),
                        "edits": [
                            {"start": "def a():", "end": "    two()", "lines": ["def a():", "    three()"]},
                            {"append": True, "lines": ["", "", "def c():", "    pass"]},
                        ],
                    },
                ),
                tool_call(
                    2,
                    "move",
                    {
                        "path": str(path),
                        "start": "def b():",
                        "end": "    pass",
                        "append": True,
                        "to_path": str(other),
                    },
                ),
                tool_call(
                    3,
                    "substitute",
                    {"path": str(path), "pattern": "three", "replacement": "four"},
                ),
            )[:3]

            for response in responses:
                self.assertIs(dig(response, "result", "isError"), False, response)
            self.assertEqual(
                path.read_text(), "def a():\n    four()\n\n\ndef c():\n    pass\n"
            )
            self.assertEqual(other.read_text(), "import os\n\n\ndef b():\n    pass\n")

    def test_move_refuses_arguments_its_schema_lacks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "a.txt"
            _ = path.write_text("head line\n    body line\ntail line\n")

            response = exchange(
                tool_call(
                    1,
                    "move",
                    {"path": str(path), "start": "head line", "block": True, "append": True},
                ),
            )[0]
            content = path.read_text()

        self.assertIs(dig(response, "result", "isError"), True)
        self.assertIn("move does not take block", str(dig(response, "result", "content", 0, "text")))
        self.assertEqual(content, "head line\n    body line\ntail line\n")

    def test_unexpected_exception_is_reported_and_server_keeps_serving(self) -> None:
        def explode(_store: AnchorStore, _arguments: dict[str, object]) -> str:
            raise ValueError("boom")

        with mock.patch.dict(server.TOOL_HANDLERS, {"read": explode}):
            failure, pong = exchange(
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "tools/call",
                    "params": {"name": "read", "arguments": {}},
                },
                {"jsonrpc": "2.0", "id": 2, "method": "ping"},
            )[:2]

        self.assertIs(dig(failure, "result", "isError"), True)
        self.assertEqual(
            dig(failure, "result", "content", 0, "text"),
            "[E_INTERNAL] ValueError: boom",
        )
        self.assertEqual(dig(pong, "result"), {})


if __name__ == "__main__":
    _ = unittest.main()
