"""`batch` contracts against temporary files: one write, checks, and overlaps."""

import random
import re
import tempfile
import unittest
from pathlib import Path
from typing import override

from hashline_mcp.anchors import AnchorStore
from hashline_mcp.batch import batch_edit
from hashline_mcp.errors import ToolError
from hashline_mcp.tools import read_file

ROW = re.compile(r"^[+ ]?([a-z]{3,})│(.*)$")


def anchors_by_line(output: str) -> dict[str, str]:
    """Map line content to anchor for every row in a tool result."""
    matches = (ROW.match(line) for line in output.splitlines())
    return {match.group(2): match.group(1) for match in matches if match is not None}


def replace(first: str, last: str, anchors: dict[str, str], lines: list[str]) -> dict[str, object]:
    return {
        "op": "replace",
        "first": anchors[first],
        "first_text": first,
        "last": anchors[last],
        "last_text": last,
        "lines": lines,
    }


def insert(anchor: str, position: str, anchors: dict[str, str], lines: list[str]) -> dict[str, object]:
    return {
        "op": "insert",
        "anchor": anchors[anchor],
        "anchor_text": anchor,
        "position": position,
        "lines": lines,
    }


class BatchTests(unittest.TestCase):
    @override
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.store = AnchorStore(random.Random(11))

    def write(self, name: str, data: bytes) -> str:
        path = self.root / name
        _ = path.write_bytes(data)
        return str(path)

    def assert_refused(self, code: str, path: str, edits: object) -> str:
        """Assert `edits` are refused with `code` and leave the file as it was."""
        before = Path(path).read_bytes()
        with self.assertRaises(ToolError) as caught:
            _ = batch_edit(self.store, path, edits)
        self.assertEqual(caught.exception.code, code)
        self.assertEqual(Path(path).read_bytes(), before)
        return str(caught.exception)

    def test_applies_every_edit_in_one_write_and_keeps_other_anchors(self) -> None:
        path = self.write("a.txt", b"one\ntwo\nthree\nfour\nfive\n")
        anchors = anchors_by_line(read_file(self.store, path))

        output = batch_edit(
            self.store,
            path,
            [
                replace("four", "four", anchors, ["FOUR", "FOUR+"]),
                insert("one", "after", anchors, ["one+"]),
                replace("two", "three", anchors, []),
            ],
        )

        self.assertEqual(Path(path).read_text(), "one\none+\nFOUR\nFOUR+\nfive\n")
        self.assertTrue(output.startswith(f"Applied 3 edit(s). {Path(path).resolve()}"))
        # Each `@<line>` names the first row shown under it, as in `grep`.
        # New lines come back without context; a removal shows its context.
        self.assertRegex(output, r"\n@2 edit 2\n\+[a-z]{3}│one\+\n@")
        self.assertRegex(output, r"\n@2 edit 3\n [a-z]{3}│one\+\n [a-z]{3}│FOUR\n")
        self.assertRegex(output, r"\n@3 edit 1\n\+[a-z]{3}│FOUR\n\+[a-z]{3}│FOUR\+\nFile:")
        after = anchors_by_line(read_file(self.store, path))
        self.assertEqual(after["one"], anchors["one"])
        self.assertEqual(after["five"], anchors["five"])
        self.assertEqual(after["FOUR"], anchors_by_line(output)["FOUR"])

    def test_refused_edit_writes_nothing_and_names_the_edit(self) -> None:
        path = self.write("a.txt", b"alpha\nbeta\n")
        anchors = anchors_by_line(read_file(self.store, path))
        wrong = {**anchors, "beta": anchors["alpha"]}

        message = self.assert_refused(
            "E_CONTENT_MISMATCH",
            path,
            [
                replace("alpha", "alpha", anchors, ["A"]),
                replace("beta", "beta", wrong, ["B"]),
            ],
        )
        self.assertTrue(message.startswith("[E_CONTENT_MISMATCH] Edit 2: "))

    def test_refuses_overlapping_edits(self) -> None:
        path = self.write("a.txt", b"a1\nb2\nc3\n")
        anchors = anchors_by_line(read_file(self.store, path))

        message = self.assert_refused(
            "E_BAD_REQUEST",
            path,
            [
                replace("a1", "b2", anchors, ["x"]),
                replace("b2", "c3", anchors, ["y"]),
            ],
        )
        self.assertIn("Edits 1 and 2 overlap", message)
        _ = self.assert_refused(
            "E_BAD_REQUEST",
            path,
            [
                replace("a1", "c3", anchors, ["x"]),
                insert("b2", "after", anchors, ["y"]),
            ],
        )

    def test_inserts_at_the_edges_of_a_replaced_range(self) -> None:
        path = self.write("a.txt", b"a1\nb2\nc3\nd4\n")
        anchors = anchors_by_line(read_file(self.store, path))

        _ = batch_edit(
            self.store,
            path,
            [
                replace("b2", "c3", anchors, ["new"]),
                insert("c3", "after", anchors, ["tail"]),
                insert("b2", "before", anchors, ["head"]),
                insert("a1", "after", anchors, ["head2"]),
            ],
        )

        self.assertEqual(
            Path(path).read_text(), "a1\nhead\nhead2\nnew\ntail\nd4\n"
        )

    def test_insert_beside_a_removal_of_every_line(self) -> None:
        path = self.write("a.txt", b"a1\nb2\n")
        anchors = anchors_by_line(read_file(self.store, path))

        _ = batch_edit(
            self.store,
            path,
            [
                insert("a1", "before", anchors, ["only"]),
                replace("a1", "b2", anchors, []),
            ],
        )

        self.assertEqual(Path(path).read_text(), "only\n")
        self.assertEqual(len(self.store.files[Path(path).resolve()].anchors), 1)

    def test_an_edit_that_changes_nothing_still_overlaps(self) -> None:
        path = self.write("a.txt", b"a1\nb2\nc3\n")
        anchors = anchors_by_line(read_file(self.store, path))

        message = self.assert_refused(
            "E_BAD_REQUEST",
            path,
            [
                replace("a1", "c3", anchors, ["a1", "b2", "c3"]),
                replace("b2", "b2", anchors, ["x"]),
            ],
        )
        self.assertIn("Edits 1 and 2 overlap", message)

    def test_skips_edits_that_change_nothing(self) -> None:
        path = self.write("a.txt", b"same\nold\n")
        anchors = anchors_by_line(read_file(self.store, path))

        unchanged = batch_edit(
            self.store, path, [replace("same", "same", anchors, ["same"])]
        )
        output = batch_edit(
            self.store,
            path,
            [
                replace("same", "same", anchors, ["same"]),
                replace("old", "old", anchors, ["new"]),
            ],
        )

        self.assertEqual(unchanged, "No change: every edit leaves the file as it is.")
        self.assertIn("Applied 1 edit(s), skipped 1 that changed nothing.", output)
        self.assertEqual(Path(path).read_text(), "same\nnew\n")
        self.assertEqual(
            anchors_by_line(read_file(self.store, path))["same"], anchors["same"]
        )

    def test_inserts_into_an_empty_file(self) -> None:
        path = self.write("empty.txt", b"")
        anchor = read_file(self.store, path).split("│")[0]

        _ = batch_edit(
            self.store,
            path,
            [
                {
                    "op": "insert",
                    "anchor": anchor,
                    "anchor_text": "",
                    "position": "after",
                    "lines": ["first", "second"],
                }
            ],
        )

        self.assertEqual(Path(path).read_text(), "first\nsecond\n")

    def test_refuses_malformed_edits(self) -> None:
        path = self.write("a.txt", b"line\n")
        anchors = anchors_by_line(read_file(self.store, path))
        good = replace("line", "line", anchors, ["x"])

        no_lines: list[str] = []
        cases: list[tuple[object, str]] = [
            (no_lines, "non-empty array"),
            ("nope", "non-empty array"),
            ([good, "nope"], "Edit 2: each edit must be an object"),
            ([{"op": "move", "lines": no_lines}], 'op must be "replace" or "insert"'),
            ([{"op": "insert", "lines": no_lines}], "exactly the fields"),
            ([{**good, "position": "after"}], "exactly the fields"),
            ([{**good, "first": 3}], "first must be a string"),
        ]
        for edits, fragment in cases:
            with self.subTest(edits=edits):
                message = self.assert_refused("E_BAD_REQUEST", path, edits)
                self.assertIn(fragment, message)

    def test_edits_several_files_named_on_each_edit(self) -> None:
        first = self.write("a.txt", b"a1\na2\n")
        second = self.write("b.txt", b"b1\nb2\n")
        anchors = anchors_by_line(read_file(self.store, first) + "\n" + read_file(self.store, second))

        output = batch_edit(
            self.store,
            None,
            [
                {**replace("b2", "b2", anchors, ["B2"]), "path": second},
                {**insert("a1", "after", anchors, ["a1+"]), "path": first},
                {**replace("b1", "b1", anchors, ["B1"]), "path": second},
            ],
        )

        self.assertEqual(Path(first).read_text(), "a1\na1+\na2\n")
        self.assertEqual(Path(second).read_text(), "B1\nB2\n")
        self.assertTrue(output.startswith("Applied 3 edit(s) to 2 file(s).\n"))
        self.assertIn(f"\n{Path(first).resolve()}\n@2 edit 2\n", output)
        self.assertIn(f"\n{Path(second).resolve()}\n@1 edit 3\n", output)

    def test_range_edits_and_appends_without_reading(self) -> None:
        path = self.write("a.py", b"def a():\n    one()\n\n\ndef b():\n    two()\n\n\ndef c():\n    pass\n")

        _ = batch_edit(
            self.store,
            path,
            [
                {"op": "replace", "first_text": "def b():", "last_text": "    two()", "lines": []},
                {
                    "op": "replace",
                    "first_text": "def c():",
                    "last_text": "    pass",
                    "lines": ["def c():", "    three()"],
                },
                {"op": "insert", "append": True, "lines": ["", "", "x = 1"]},
            ],
        )

        self.assertEqual(
            Path(path).read_text(),
            "def a():\n    one()\n\n\n\n\ndef c():\n    three()\n\n\nx = 1\n",
        )

    def test_append_with_blank_lines_sets_the_separation(self) -> None:
        path = self.write("a.py", b"x = 1\n\n")

        _ = batch_edit(
            self.store,
            path,
            [{"op": "insert", "append": True, "blank_lines": 2, "lines": ["", "y = 2"]}],
        )

        self.assertEqual(Path(path).read_text(), "x = 1\n\n\ny = 2\n\n")

    def test_an_edit_path_overrides_the_batch_path(self) -> None:
        first = self.write("a.txt", b"a1\n")
        second = self.write("b.txt", b"b1\n")
        anchors = anchors_by_line(read_file(self.store, first) + "\n" + read_file(self.store, second))

        _ = batch_edit(
            self.store,
            first,
            [
                replace("a1", "a1", anchors, ["A1"]),
                {**replace("b1", "b1", anchors, ["B1"]), "path": second},
            ],
        )

        self.assertEqual(Path(first).read_text(), "A1\n")
        self.assertEqual(Path(second).read_text(), "B1\n")

    def test_a_refusal_in_one_file_writes_no_file(self) -> None:
        first = self.write("a.txt", b"a1\n")
        second = self.write("b.txt", b"b1\n")
        anchors = anchors_by_line(read_file(self.store, first) + "\n" + read_file(self.store, second))

        with self.assertRaises(ToolError) as caught:
            _ = batch_edit(
                self.store,
                None,
                [
                    {**replace("a1", "a1", anchors, ["A1"]), "path": first},
                    {**replace("b1", "b1", anchors, ["B1"]), "last_text": "x", "path": second},
                ],
            )

        self.assertTrue(str(caught.exception).startswith("[E_CONTENT_MISMATCH] Edit 2: "))
        self.assertEqual(Path(first).read_text(), "a1\n")
        self.assertEqual(Path(second).read_text(), "b1\n")

    def test_edits_lines_named_by_text_alone_across_files(self) -> None:
        first = self.write("a.txt", b"rate = 0.01\nlimit = 20\n")
        second = self.write("b.txt", b"def run():\n    pass\n")

        _ = batch_edit(
            self.store,
            None,
            [
                {"path": first, "op": "replace", "first_text": "rate = 0.01", "last_text": "rate = 0.01", "lines": ["rate = 0.02"]},
                {"path": second, "op": "insert", "anchor_text": "def run():", "position": "after", "lines": ["    audit()"]},
            ],
        )

        self.assertEqual(Path(first).read_text(), "rate = 0.02\nlimit = 20\n")
        self.assertEqual(Path(second).read_text(), "def run():\n    audit()\n    pass\n")

    def test_refuses_an_edit_without_any_path(self) -> None:
        path = self.write("a.txt", b"line\n")
        anchors = anchors_by_line(read_file(self.store, path))

        with self.assertRaises(ToolError) as caught:
            _ = batch_edit(self.store, None, [replace("line", "line", anchors, ["x"])])

        self.assertEqual(caught.exception.code, "E_BAD_REQUEST")
        self.assertIn("Edit 1: give a path", str(caught.exception))


if __name__ == "__main__":
    _ = unittest.main()
