"""Compact line references and edits, as the MCP tools accept them."""

import unittest

from hashline_mcp.edit import expand_edits, parse_line_ref
from hashline_mcp.errors import ToolError


class LineRefTests(unittest.TestCase):
    def test_a_row_gives_its_anchor_and_text(self) -> None:
        cases = [
            ("abc│    rate = 0.04", ("abc", "    rate = 0.04")),
            ("+abc│new line", ("abc", "new line")),
            (" abc│context", ("abc", "context")),
            ("abc│", ("abc", "")),
        ]
        for value, expected in cases:
            with self.subTest(value=value):
                self.assertEqual(parse_line_ref(value, "start"), expected)

    def test_other_text_is_text_alone(self) -> None:
        for value in ("def run():", "ABC│x", "a│b", "    abc│x"):
            with self.subTest(value=value):
                self.assertEqual(parse_line_ref(value, "start"), (None, value))

    def test_refuses_a_value_that_is_not_a_string(self) -> None:
        with self.assertRaises(ToolError) as caught:
            _ = parse_line_ref(3, "after")

        self.assertEqual(caught.exception.message, "after must be a string")


class ExpandEditsTests(unittest.TestCase):
    def test_expands_replacements_and_insertions(self) -> None:
        expanded = expand_edits(
            [
                {"start": "abc│first", "end": "last line text", "lines": ["x"]},
                {"start": "only", "lines": [], "path": "b.txt"},
                {"before": "def run():", "lines": ["y"]},
            ]
        )

        self.assertEqual(
            expanded,
            [
                {
                    "lines": ["x"],
                    "op": "replace",
                    "first": "abc",
                    "first_text": "first",
                    "last_text": "last line text",
                },
                {
                    "lines": [],
                    "path": "b.txt",
                    "op": "replace",
                    "first_text": "only",
                    "last_text": "only",
                },
                {
                    "lines": ["y"],
                    "op": "insert",
                    "anchor_text": "def run():",
                    "position": "before",
                },
            ],
        )

    def test_expands_appends(self) -> None:
        expanded = expand_edits([{"append": True, "lines": ["z"], "path": "b.txt"}])

        self.assertEqual(
            expanded,
            [
                {
                    "lines": ["z"],
                    "path": "b.txt",
                    "op": "insert",
                    "append": True,
                },
            ],
        )

    def test_refuses_edits_without_exactly_one_target(self) -> None:
        cases: list[dict[str, object]] = [
            {"lines": []},
            {"start": "a", "after": "b", "lines": []},
            {"after": "a", "end": "b", "lines": []},
            {"start": "a", "first": "abc", "lines": []},
            {"start": "a", "block": True, "lines": []},
            {"append": True, "after": "a", "lines": []},
            {"append": False, "lines": []},
        ]
        for edit in cases:
            with self.subTest(edit=edit), self.assertRaises(ToolError) as caught:
                _ = expand_edits([{"start": "fine", "lines": []}, edit])
            self.assertEqual(caught.exception.code, "E_BAD_REQUEST")
            self.assertTrue(caught.exception.message.startswith("Edit 2: "))

    def test_leaves_other_shapes_for_the_batch_to_refuse(self) -> None:
        self.assertEqual(expand_edits("nope"), "nope")
        self.assertEqual(expand_edits(["nope"]), ["nope"])


if __name__ == "__main__":
    _ = unittest.main()
