"""Tool contracts against temporary files: anchors, edits, and refusals."""

import random
import re
import tempfile
import time
import unittest
from pathlib import Path
from typing import override

from hashline_mcp.anchors import AnchorStore, carry_anchors
from hashline_mcp.errors import ToolError
from hashline_mcp.text_file import decode_text, load_text_file
from hashline_mcp.tools import (
    insert_lines,
    parse_anchor,
    read_file,
    replace_lines,
)

ROW = re.compile(r"^[+ ]?([a-z]{3,})│(.*)$")


def anchors_by_line(output: str) -> dict[str, str]:
    """Map line content to anchor for every row in a tool result."""
    matches = (ROW.match(line) for line in output.splitlines())
    return {match.group(2): match.group(1) for match in matches if match is not None}


def line_text(store: AnchorStore, path: str, anchor: str) -> str:
    """The tracked content of `anchor`'s line, or "" when it is unknown, so
    tests not about the content check pass it trivially."""
    tracked = store.files.get(Path(path).resolve())
    if tracked is None:
        return ""
    index = tracked.positions.get(parse_anchor(anchor, "anchor"))
    return tracked.content.lines[index] if index is not None else ""


def replace(store: AnchorStore, path: str, first: str, last: str, lines: object) -> str:
    first_text = line_text(store, path, first)
    last_text = line_text(store, path, last)
    return replace_lines(store, path, first, first_text, last, last_text, lines)


def insert(
    store: AnchorStore, path: str, anchor: str, position: str, lines: object
) -> str:
    anchor_text = line_text(store, path, anchor)
    return insert_lines(store, path, anchor, anchor_text, position, lines)


class ToolTests(unittest.TestCase):
    @override
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.store = AnchorStore(random.Random(7))

    def write(self, name: str, data: bytes) -> str:
        path = self.root / name
        _ = path.write_bytes(data)
        return str(path)

    def test_read_renders_anchor_rows_and_pages(self) -> None:
        path = self.write("a.txt", b"one\ntwo\nthree\n")

        output = read_file(self.store, path, offset=2, limit=1)

        self.assertRegex(
            output,
            r"^[a-z]{3}│two\n\[Showing lines 2-2 of 3\. Use offset=3 to continue\.\]$",
        )

    def test_read_from_the_end_reports_the_file(self) -> None:
        path = self.write("a.txt", b"one\ntwo\nthree")

        output = read_file(self.store, path, offset=-2)

        self.assertRegex(
            output,
            r"^[a-z]{3}│two\n[a-z]{3}│three\n\[Showing lines 2-3 of 3\.\]\n"
            + r"File: LF line endings, no final newline\.$",
        )
        self.assertIn("one", read_file(self.store, path, offset=-10))
        with self.assertRaises(ToolError):
            _ = read_file(self.store, path, offset=0)

    def test_rows_cut_by_the_size_cap_stay_unserved(self) -> None:
        long_line = "x" * 1500
        path = self.write("a.txt", (long_line + "\n").encode() * 60)

        output = read_file(self.store, path)
        tracked = self.store.files[Path(path).resolve()]

        self.assertIn("Use offset=", output)
        shown = len(output.splitlines()) - 1
        self.assertEqual(tracked.served, set(tracked.anchors[:shown]))

    def test_chained_edits_reuse_anchors_from_one_read(self) -> None:
        path = self.write("a.py", b"a\nb\nc\nd\ne\n")
        anchors = anchors_by_line(read_file(self.store, path))

        _ = replace(self.store, path, anchors["b"], anchors["b"], ["b1", "b2", "b3"])
        _ = replace(self.store, path, anchors["d"], anchors["e"], ["de"])

        self.assertEqual(Path(path).read_bytes(), b"a\nb1\nb2\nb3\nc\nde\n")

    def test_edit_result_anchors_address_new_lines(self) -> None:
        path = self.write("a.py", b"x\ny\n")
        anchors = anchors_by_line(read_file(self.store, path))

        result = insert(self.store, path, anchors["x"], "after", ["new"])
        new_anchor = anchors_by_line(result)["new"]
        _ = replace(self.store, path, new_anchor, new_anchor, ["newer"])

        self.assertIn("+" + new_anchor + "│new", result)
        self.assertEqual(Path(path).read_text(), "x\nnewer\ny\n")

    def test_insert_before_and_delete_range(self) -> None:
        path = self.write("a.txt", b"a\nb\nc\n")
        anchors = anchors_by_line(read_file(self.store, path))

        _ = insert(self.store, path, anchors["a"], "before", ["top"])
        _ = replace(self.store, path, anchors["b"], anchors["c"], [])

        self.assertEqual(Path(path).read_text(), "top\na\n")

    def test_deleting_every_line_leaves_an_editable_empty_file(self) -> None:
        path = self.write("a.txt", b"a\nb\n")
        anchors = anchors_by_line(read_file(self.store, path))

        _ = replace(self.store, path, anchors["a"], anchors["b"], [])
        row = read_file(self.store, path)
        _ = insert(self.store, path, row.split("│")[0], "after", ["fresh"])

        self.assertEqual(Path(path).read_text(), "fresh\n")
        self.assert_tracked_matches_disk(path)

    def test_edits_fill_an_empty_file_with_terminated_lines(self) -> None:
        cases = [
            ("replace", b"x = 1\n"),
            ("before", b"x = 1\n"),
            ("after", b"x = 1\n"),
        ]
        for operation, expected in cases:
            with self.subTest(operation):
                path = self.write(f"{operation}.py", b"")
                row = read_file(self.store, path).split("│")[0]

                if operation == "replace":
                    _ = replace(self.store, path, row, row, ["x = 1"])
                else:
                    _ = insert(self.store, path, row, operation, ["x = 1"])

                self.assertEqual(Path(path).read_bytes(), expected)
                self.assert_tracked_matches_disk(path)

    def test_emptied_file_edits_like_a_fresh_empty_file(self) -> None:
        path = self.write("a.txt", b"\xef\xbb\xbf")
        row = read_file(self.store, path).split("│")[0]

        result = insert(self.store, path, row, "before", ["a", "b"])
        anchors = anchors_by_line(result)
        _ = replace(self.store, path, anchors["a"], anchors["b"], [])
        self.assertEqual(Path(path).read_bytes(), b"\xef\xbb\xbf")
        self.assert_tracked_matches_disk(path)

        row = read_file(self.store, path).split("│")[0]
        _ = replace(self.store, path, row, row, ["c"])
        self.assertEqual(Path(path).read_bytes(), b"\xef\xbb\xbfc\n")
        self.assert_tracked_matches_disk(path)

    def assert_tracked_matches_disk(self, path: str) -> None:
        """Assert the served state of `path` is what a fresh read would decode."""
        tracked = self.store.files[Path(path).resolve()]
        fresh = decode_text(Path(path).read_bytes(), Path(path))
        self.assertEqual(tracked.content, fresh)
        self.assertEqual(len(tracked.anchors), len(fresh.lines))

    def test_line_endings_bom_and_missing_final_newline_survive(self) -> None:
        path = self.write("a.txt", b"\xef\xbb\xbfone\r\ntwo\r\nlast")
        anchors = anchors_by_line(read_file(self.store, path))

        _ = replace(self.store, path, anchors["two"], anchors["two"], ["2", "2b"])
        _ = insert(self.store, path, anchors["last"], "after", ["tail"])

        self.assertEqual(
            Path(path).read_bytes(), b"\xef\xbb\xbfone\r\n2\r\n2b\r\nlast\r\ntail"
        )

    def test_edits_leaving_an_empty_last_line_end_it(self) -> None:
        cases = [
            ("insert", b"a\nx\n\n"),
            ("replace", b"a\n\n"),
        ]
        for operation, expected in cases:
            with self.subTest(operation):
                path = self.write(f"{operation}.txt", b"a\nx")
                anchors = anchors_by_line(read_file(self.store, path))

                if operation == "insert":
                    _ = insert(self.store, path, anchors["x"], "after", [""])
                else:
                    _ = replace(self.store, path, anchors["x"], anchors["x"], [""])

                self.assertEqual(Path(path).read_bytes(), expected)
                self.assert_tracked_matches_disk(path)

    def test_a_carriage_return_before_a_written_newline_joins_the_ending(self) -> None:
        # Content ending in "\r" written with a "\n" terminator is a CRLF line
        # on disk, so the tracked line must drop the "\r" as a fresh read does.
        cases = [
            (
                "stray-final-cr",
                b"first\nlast here\r",
                "insert",
                ["appended"],
                b"first\nlast here\r\nappended",
            ),
            (
                "replace-with-cr",
                b"first\nlast here\n",
                "replace",
                ["new\r\r"],
                b"first\nnew\r\n",
            ),
            (
                "insert-with-cr",
                b"first\nlast here\n",
                "insert",
                ["new\r\r"],
                b"first\nlast here\nnew\r\n",
            ),
        ]
        for name, data, operation, lines, expected in cases:
            with self.subTest(name):
                path = self.write(f"{name}.txt", data)
                _ = read_file(self.store, path)
                last = self.store.files[Path(path).resolve()].anchors[-1]

                if operation == "insert":
                    _ = insert(self.store, path, last, "after", lines)
                else:
                    _ = replace(self.store, path, last, last, lines)

                self.assertEqual(Path(path).read_bytes(), expected)
                self.assert_tracked_matches_disk(path)

    def test_deleting_the_last_line_keeps_the_missing_final_newline(self) -> None:
        path = self.write("a.txt", b"a\nx")
        anchors = anchors_by_line(read_file(self.store, path))

        _ = replace(self.store, path, anchors["x"], anchors["x"], [])

        self.assertEqual(Path(path).read_bytes(), b"a")
        self.assert_tracked_matches_disk(path)

    def test_new_process_assigns_unchanged_file_the_same_anchors(self) -> None:
        path = self.write("a.txt", b"a\nb\n")
        first = read_file(self.store, path)

        restarted = AnchorStore(random.Random(99))
        anchors = anchors_by_line(first)
        with self.assertRaises(ToolError) as caught:
            _ = replace_lines(
                restarted, path, anchors["a"], "a", anchors["a"], "a", ["x"]
            )

        self.assertEqual(caught.exception.code, "E_RANGE_UNSERVED")
        self.assertEqual(read_file(restarted, path), first)

    def test_wrong_row_anchor_is_refused_by_content_check(self) -> None:
        path = self.write(
            "a.py", b"def format_usage(self):\n    pass\ndef format_help(self):\n"
        )
        anchors = anchors_by_line(read_file(self.store, path))
        usage = anchors["def format_usage(self):"]

        with self.assertRaises(ToolError) as caught:
            _ = replace_lines(
                self.store,
                path,
                usage,
                "def format_help(",
                usage,
                "def format_help(",
                ["x"],
            )

        self.assertEqual(caught.exception.code, "E_CONTENT_MISMATCH")
        self.assertIn("│def format_help(self):", str(caught.exception))
        self.assertTrue(Path(path).read_text().startswith("def format_usage"))

    def test_content_check_accepts_prefixes_rows_and_short_lines(self) -> None:
        path = self.write("a.py", b"    value = compute_something(x)\n}\n\n")
        anchors = anchors_by_line(read_file(self.store, path))
        value, brace, blank = (
            anchors["    value = compute_something(x)"],
            anchors["}"],
            anchors[""],
        )

        _ = insert_lines(
            self.store, path, value, "value = compute_s", "before", ["# a"]
        )
        _ = insert_lines(self.store, path, brace, f"{brace}│}}", "after", ["# b"])
        _ = insert_lines(self.store, path, blank, "", "after", ["# c"])

        self.assertEqual(
            Path(path).read_text(),
            "# a\n    value = compute_something(x)\n}\n# b\n\n# c\n",
        )

    def test_content_check_accepts_delimiter_content_and_truncated_rows(self) -> None:
        long_line = "x = '" + "y" * 2100 + "'"
        path = self.write("a.txt", f"name│value\n{long_line}\n".encode())
        rows = read_file(self.store, path).splitlines()
        anchors = anchors_by_line(read_file(self.store, path))
        name = anchors["name│value"]
        long_anchor, shown = rows[1].split("│", 1)

        _ = replace_lines(
            self.store, path, name, "name│value", name, "name│value", ["n"]
        )
        _ = replace_lines(
            self.store, path, long_anchor, shown, long_anchor, rows[1], ["z"]
        )

        self.assertEqual(Path(path).read_text(), "n\nz\n")

    def test_too_short_content_check_is_refused(self) -> None:
        path = self.write("a.py", b"    value = compute_something(x)\n")
        anchors = anchors_by_line(read_file(self.store, path))
        value = anchors["    value = compute_something(x)"]

        for text in ("value", "value = compute_somethinG"):
            with self.subTest(text=text), self.assertRaises(ToolError) as caught:
                _ = replace_lines(self.store, path, value, text, value, text, ["x"])
            self.assertEqual(caught.exception.code, "E_CONTENT_MISMATCH")

    def test_stale_anchor_is_refused_with_current_rows(self) -> None:
        path = self.write("a.txt", b"a\nb\nc\n")
        anchors = anchors_by_line(read_file(self.store, path))
        _ = replace(self.store, path, anchors["b"], anchors["b"], ["B"])

        with self.assertRaises(ToolError) as caught:
            _ = replace(self.store, path, anchors["b"], anchors["b"], ["again"])

        self.assertEqual(caught.exception.code, "E_STALE_ANCHOR")
        self.assertIn("│B", str(caught.exception))
        self.assertEqual(Path(path).read_text(), "a\nB\nc\n")

    def test_unknown_anchor_is_refused(self) -> None:
        path = self.write("a.txt", b"a\n")

        with self.assertRaises(ToolError) as caught:
            _ = replace(self.store, path, "zzz", "zzz", ["x"])

        self.assertEqual(caught.exception.code, "E_STALE_ANCHOR")
        self.assertIn("read the file", caught.exception.message)

    def test_unknown_anchor_shows_the_served_rows_its_text_starts(self) -> None:
        path = self.write(
            "a.py", b"def keep_this_one():\n    return 1\ndef keep_this_one_too():\n"
        )
        anchors = anchors_by_line(read_file(self.store, path))

        with self.assertRaises(ToolError) as caught:
            text = "def keep_this_one"
            _ = replace_lines(self.store, path, "zzz", text, "zzz", text, ["x"])

        self.assertEqual(caught.exception.code, "E_STALE_ANCHOR")
        message = caught.exception.message
        self.assertIn(f"{anchors['def keep_this_one():']}│def keep_this_one():", message)
        self.assertIn(
            f"{anchors['def keep_this_one_too():']}│def keep_this_one_too():", message
        )
        self.assertNotIn("return 1", message)
        self.assertIn("Retry with the anchor", message)

    def test_unknown_anchor_shows_only_served_rows(self) -> None:
        path = self.write("a.txt", b"alpha beta gamma one\nalpha beta gamma two\n")
        _ = read_file(self.store, path, offset=1, limit=1)

        with self.assertRaises(ToolError) as caught:
            _ = insert_lines(self.store, path, "zzz", "alpha beta gamma", "after", ["x"])

        self.assertIn("│alpha beta gamma one", caught.exception.message)
        self.assertNotIn("alpha beta gamma two", caught.exception.message)

    def test_unseen_lines_are_refused_and_then_editable(self) -> None:
        path = self.write("a.txt", b"a\nb\nc\n")
        anchors = anchors_by_line(read_file(self.store, path, limit=1))
        tracked = self.store.files[Path(path).resolve()]
        last = tracked.anchors[2]

        with self.assertRaises(ToolError) as caught:
            _ = replace(self.store, path, anchors["a"], last, ["x"])
        _ = replace(self.store, path, anchors["a"], last, ["x"])

        self.assertEqual(caught.exception.code, "E_RANGE_UNSERVED")
        self.assertEqual(Path(path).read_text(), "x\n")

    def test_outside_change_keeps_anchors_of_untouched_lines(self) -> None:
        path = self.write("a.txt", b"alpha\nbeta\ngamma\ndelta\nomega\n")
        anchors = anchors_by_line(read_file(self.store, path))
        _ = Path(path).write_text("zero\nalpha\nbeta\nGAMMA\ndelta\nomega\n")

        _ = replace(self.store, path, anchors["alpha"], anchors["alpha"], ["A"])
        _ = replace(self.store, path, anchors["omega"], anchors["omega"], ["O"])
        with self.assertRaises(ToolError) as caught:
            _ = replace(self.store, path, anchors["gamma"], anchors["gamma"], ["g"])

        self.assertEqual(caught.exception.code, "E_STALE_ANCHOR")
        self.assertIn("│GAMMA", str(caught.exception))
        self.assertEqual(Path(path).read_text(), "zero\nA\nbeta\nGAMMA\ndelta\nO\n")

    def test_range_spanning_an_outside_deletion_is_reshown(self) -> None:
        path = self.write("a.txt", b"p\nq\nr\ns\n")
        anchors = anchors_by_line(read_file(self.store, path))
        _ = Path(path).write_text("p\ns\n")

        with self.assertRaises(ToolError) as caught:
            _ = replace(self.store, path, anchors["p"], anchors["s"], ["P", "S"])
        _ = replace(self.store, path, anchors["p"], anchors["s"], ["P", "S"])

        self.assertEqual(caught.exception.code, "E_RANGE_UNSERVED")
        self.assertEqual(Path(path).read_text(), "P\nS\n")

    def test_range_may_span_lines_never_shown(self) -> None:
        path = self.write("a.txt", b"a\nb\nc\nd\ne\n")
        anchors = anchors_by_line(read_file(self.store, path, limit=1))
        anchors |= anchors_by_line(read_file(self.store, path, offset=5))

        _ = replace(self.store, path, anchors["a"], anchors["e"], ["x"])

        self.assertEqual(Path(path).read_text(), "x\n")

    def test_range_spanning_a_line_changed_outside_is_reshown(self) -> None:
        path = self.write("a.txt", b"a\nb\nc\nd\ne\n")
        anchors = anchors_by_line(read_file(self.store, path))
        _ = Path(path).write_text("a\nb\nC\nd\ne\n")

        with self.assertRaises(ToolError) as caught:
            _ = replace(self.store, path, anchors["a"], anchors["e"], ["x"])
        _ = replace(self.store, path, anchors["a"], anchors["e"], ["x"])

        self.assertEqual(caught.exception.code, "E_RANGE_UNSERVED")
        self.assertIn("│C", caught.exception.message)
        self.assertEqual(Path(path).read_text(), "x\n")

    def test_long_unserved_range_refusal_shows_its_last_row(self) -> None:
        lines = [f"line {index}" for index in range(100)]
        path = self.write("a.txt", ("\n".join(lines) + "\n").encode())
        anchors = anchors_by_line(read_file(self.store, path, limit=1))
        last = self.store.files[Path(path).resolve()].anchors[99]

        with self.assertRaises(ToolError) as caught:
            _ = replace_lines(self.store, path, anchors["line 0"], "line 0", last, "line 99", ["x"])
        _ = replace_lines(self.store, path, anchors["line 0"], "line 0", last, "line 99", ["x"])

        self.assertIn("39 more line(s) in the range; read offset=61", caught.exception.message)
        self.assertIn(f"{last}│line 99", caught.exception.message)
        self.assertEqual(Path(path).read_text(), "x\n")

    def test_new_lines_are_split_and_copied_rows_only_warned(self) -> None:
        path = self.write("a.txt", b"a\nb\n")
        anchors = anchors_by_line(read_file(self.store, path))

        result = replace(self.store, path, anchors["a"], anchors["a"], "one\ntwo")
        rows = anchors_by_line(result)
        copied = [f"{rows['one']}│ONE", f"+{rows['two']}│TWO"]
        second = replace(self.store, path, rows["one"], rows["two"], copied)

        self.assertIn("like copied rows", second)
        self.assertEqual(
            Path(path).read_text(), "".join(line + "\n" for line in copied) + "b\n"
        )

    def test_pasted_row_is_accepted_as_anchor(self) -> None:
        path = self.write("a.txt", b"a\nb\n")
        anchors = anchors_by_line(read_file(self.store, path))

        _ = replace(self.store, path, f"+{anchors['a']}│a", f" {anchors['b']}", ["ab"])

        self.assertEqual(Path(path).read_text(), "ab\n")

    def test_duplicate_boundary_line_warns(self) -> None:
        path = self.write("a.py", b"def f():\n    return 1\n")
        anchors = anchors_by_line(read_file(self.store, path))

        result = replace(
            self.store,
            path,
            anchors["    return 1"],
            anchors["    return 1"],
            ["def f():", "    return 2"],
        )

        self.assertIn("repeats line 1", result)

    def test_identical_replacement_does_not_write(self) -> None:
        path = self.write("a.txt", b"a\n")
        anchors = anchors_by_line(read_file(self.store, path))
        before = Path(path).stat().st_mtime_ns

        result = replace(self.store, path, anchors["a"], anchors["a"], ["a"])

        self.assertTrue(result.startswith("No change"))
        self.assertEqual(Path(path).stat().st_mtime_ns, before)

    def test_symlink_target_is_edited_and_link_kept(self) -> None:
        target = Path(self.write("target.txt", b"a\n"))
        link = self.root / "link.txt"
        link.symlink_to(target)
        anchors = anchors_by_line(read_file(self.store, str(link)))

        _ = replace(self.store, str(link), anchors["a"], anchors["a"], ["b"])

        self.assertTrue(link.is_symlink())
        self.assertEqual(target.read_text(), "b\n")

    def test_file_mode_is_preserved(self) -> None:
        path = self.write("run.sh", b"echo a\n")
        Path(path).chmod(0o755)
        anchors = anchors_by_line(read_file(self.store, path))

        _ = replace(self.store, path, anchors["echo a"], anchors["echo a"], ["echo b"])

        self.assertEqual(Path(path).stat().st_mode & 0o777, 0o755)

    def test_binary_and_invalid_utf8_are_refused(self) -> None:
        for name, data in (("a.bin", b"a\0b"), ("b.txt", b"\xff\xfe")):
            with self.subTest(name=name), self.assertRaises(ToolError) as caught:
                _ = read_file(self.store, self.write(name, data))
            self.assertEqual(caught.exception.code, "E_NOT_TEXT")

    def test_bad_requests_are_refused_before_writing(self) -> None:
        path = self.write("a.txt", b"a\n")
        anchors = anchors_by_line(read_file(self.store, path))

        for first, lines in (
            (anchors["a"], [1]),
            ("A!", ["x"]),
            (anchors["a"], ["nul\0"]),
            (anchors["a"], ["\ud800"]),
        ):
            with self.subTest(first=first), self.assertRaises(ToolError) as caught:
                _ = replace(self.store, path, first, anchors["a"], lines)
            self.assertEqual(caught.exception.code, "E_BAD_REQUEST")
        self.assertEqual(Path(path).read_text(), "a\n")

    def test_replaces_a_line_named_by_text_alone_without_a_read(self) -> None:
        path = self.write("a.py", b"def keep():\n    return 1\ndef change():\n    return 2\n")

        output = replace_lines(
            self.store, path, None, "def change():", None, "def change():", ["def changed():"]
        )

        self.assertEqual(Path(path).read_text(), "def keep():\n    return 1\ndef changed():\n    return 2\n")
        self.assertIn("│def changed():", output)

    def test_text_range_ends_at_the_nearest_matching_line_after_its_start(self) -> None:
        path = self.write(
            "a.py",
            b"def one():\n    return 1\n\ndef two():\n    x = 2\n    return x\n\ndef three():\n    return x\n",
        )

        _ = replace_lines(self.store, path, None, "def two():", None, "    return x", [])

        self.assertEqual(Path(path).read_text(), "def one():\n    return 1\n\n\ndef three():\n    return x\n")

    def test_text_that_starts_several_lines_is_refused_with_them(self) -> None:
        path = self.write("a.txt", b"value = compute(1)\nother\nvalue = compute(2)\n")
        text = "value = compute("

        with self.assertRaises(ToolError) as caught:
            _ = replace_lines(self.store, path, None, text, None, text, ["x"])

        self.assertEqual(caught.exception.code, "E_TEXT_AMBIGUOUS")
        rows = anchors_by_line(caught.exception.message)
        self.assertEqual(list(rows), ["value = compute(1)", "value = compute(2)"])
        second = rows["value = compute(2)"]
        _ = replace_lines(self.store, path, second, text, second, text, ["x"])
        self.assertEqual(Path(path).read_text(), "value = compute(1)\nother\nx\n")

    def test_text_that_starts_no_line_is_refused(self) -> None:
        path = self.write("a.txt", b"alpha\n")

        with self.assertRaises(ToolError) as caught:
            _ = insert_lines(self.store, path, None, "beta", "after", ["x"])

        self.assertEqual(caught.exception.code, "E_TEXT_NOT_FOUND")
        self.assertEqual(Path(path).read_text(), "alpha\n")

    def test_inserts_after_a_line_named_by_text_alone(self) -> None:
        path = self.write("a.txt", b"alpha\nbeta\n")

        _ = insert_lines(self.store, path, None, "alpha", "after", ["inserted"])

        self.assertEqual(Path(path).read_text(), "alpha\ninserted\nbeta\n")


class CarryAnchorTests(unittest.TestCase):
    def test_short_run_of_duplicate_lines_is_reanchored(self) -> None:
        old = ["}", "x", "}", "y"]
        new = ["q", "}", "r", "}"]

        carried, retired = carry_anchors(old, ["aaa", "bbb", "ccc", "ddd"], new)

        self.assertEqual(carried, [None, None, None, None])
        self.assertEqual(set(retired), {"aaa", "bbb", "ccc", "ddd"})

    def test_unique_lines_and_long_runs_carry(self) -> None:
        old = ["head", "m1", "m2", "m3", "unique", "tail"]
        new = ["HEAD", "m1", "m2", "m3", "X", "unique", "TAIL"]

        carried, _ = carry_anchors(old, ["a", "b", "c", "d", "e", "f"], new)

        self.assertEqual(carried, [None, "b", "c", "d", None, "e", None])

    def test_large_repetitive_file_realigns_quickly_and_exactly(self) -> None:
        old: list[str] = []
        for index in range(4000):
            old += [
                f"def f{index}(x):",
                "    if x:",
                f"        return {index}",
                "    return None",
                "",
            ]
        new = list(old)
        for index in range(0, len(new), 100):
            new[index] += "  # touched"
        anchors = [str(index) for index in range(len(old))]

        started = time.perf_counter()
        carried, retired = carry_anchors(old, anchors, new)
        elapsed = time.perf_counter() - started

        self.assertLess(elapsed, 2.0)
        self.assertEqual(len(retired), 200)
        for index, anchor in enumerate(carried):
            if anchor is not None:
                self.assertEqual(old[int(anchor)], new[index])

    def test_adversarial_staggered_duplicates_stay_bounded(self) -> None:
        old = ["a0"]
        for index in range(1, 8000):
            old += [f"a{index}", f"a{index - 1}"]
        new = [line + "!" if index % 2 == 1 else line for index, line in enumerate(old)]
        new[0] = new[-1] = "changed"
        anchors = [str(index) for index in range(len(old))]

        started = time.perf_counter()
        carried, _ = carry_anchors(old, anchors, new)
        elapsed = time.perf_counter() - started

        self.assertLess(elapsed, 2.0)
        for index, anchor in enumerate(carried):
            if anchor is not None:
                self.assertEqual(old[int(anchor)], new[index])

    def test_load_rejects_missing_file(self) -> None:
        with self.assertRaises(ToolError) as caught:
            _ = load_text_file(Path("/nonexistent/hashline-mcp"))

        self.assertEqual(caught.exception.code, "E_NOT_FOUND")

    def test_decode_keeps_form_feed_inside_a_line(self) -> None:
        content = decode_text(b"a\x0cb\nc", Path("x"))

        self.assertEqual(content.lines, ["a\x0cb", "c"])
        self.assertEqual(content.endings, ["\n", ""])


if __name__ == "__main__":
    _ = unittest.main()
