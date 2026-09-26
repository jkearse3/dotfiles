"""`move` contracts against temporary files: order, anchors, and terminators."""

import random
import re
import tempfile
import unittest
from collections.abc import Callable
from pathlib import Path
from typing import override
from unittest import mock

from hashline_mcp.anchors import AnchorStore
from hashline_mcp.errors import ToolError
from hashline_mcp.move import move_lines
from hashline_mcp.text_file import Fingerprint, TextFile, write_text_file
from hashline_mcp.tools import read_file

ROW = re.compile(r"^[+ ]?([a-z]{3,})│(.*)$")


def anchors_by_line(output: str) -> dict[str, str]:
    """Map line content to anchor for every row in a tool result."""
    matches = (ROW.match(line) for line in output.splitlines())
    return {match.group(2): match.group(1) for match in matches if match is not None}


def refuse_writes_to(
    refused: Path,
) -> Callable[[Path, TextFile, Fingerprint], Fingerprint]:
    """Wrap `write_text_file` to fail for `refused` as a read-only directory would."""

    def write(path: Path, content: TextFile, expected: Fingerprint) -> Fingerprint:
        if path == refused:
            raise PermissionError(13, "Permission denied", str(path))
        return write_text_file(path, content, expected)

    return write


class MoveTests(unittest.TestCase):
    @override
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.root = Path(directory.name)
        self.addCleanup(directory.cleanup)
        self.store = AnchorStore(random.Random(13))

    def write(self, name: str, data: bytes) -> str:
        path = self.root / name
        _ = path.write_bytes(data)
        return str(path)

    def move(
        self,
        path: str,
        anchors: dict[str, str],
        first: str,
        last: str,
        target: str,
        position: str,
        to_path: str | None = None,
        target_anchors: dict[str, str] | None = None,
    ) -> str:
        at = target_anchors if target_anchors is not None else anchors
        return move_lines(
            self.store,
            path,
            anchors[first],
            first,
            anchors[last],
            last,
            at[target],
            target,
            position,
            to_path,
        )

    def test_moves_lines_down_and_keeps_every_anchor(self) -> None:
        path = self.write("a.txt", b"a1\nb2\nc3\nd4\ne5\n")
        anchors = anchors_by_line(read_file(self.store, path))

        output = self.move(path, anchors, "a1", "b2", "d4", "after")

        self.assertEqual(Path(path).read_text(), "c3\nd4\na1\nb2\ne5\n")
        self.assertEqual(anchors_by_line(read_file(self.store, path)), anchors)
        self.assertRegex(
            output,
            # The rows around the join come back, so placement needs no read.
            r"^Moved lines 1-2 after line 4; they keep their anchors\. .+\n@2\n"
            + r" [a-z]{3}│d4\n\+[a-z]{3}│a1\n\+[a-z]{3}│b2\n [a-z]{3}│e5\n"
            + r"Rows around where they were:\n@1\n [a-z]{3}│c3\n"
            + r"File: LF line endings, final newline\.$",
        )

    def test_a_long_move_shows_only_its_seams(self) -> None:
        lines = [f"line {number:02}" for number in range(12)]
        path = self.write("a.txt", ("\n".join(lines) + "\n").encode())
        anchors = anchors_by_line(read_file(self.store, path))

        output = self.move(path, anchors, "line 01", "line 10", "line 11", "after")

        self.assertIn("\n+" + anchors["line 01"] + "│line 01\n", output)
        self.assertIn("\n+" + anchors["line 02"] + "│line 02\n", output)
        self.assertIn("[6 new line(s) not shown; read offset=5 limit=6 for their anchors.]", output)
        self.assertNotIn("│line 05", output)
        self.assertIn("\n+" + anchors["line 10"] + "│line 10\n", output)

    def test_blank_lines_set_the_spacing_at_both_places(self) -> None:
        source = self.write(
            "a.py",
            b"def a():\n    pass\n\n\n\n\ndef moved():\n    pass\n\n\ndef b():\n    pass\n",
        )
        target = self.write("b.py", b"x = 1\n\n\n\n")

        output = move_lines(
            self.store, source, None, "def moved():", None, "    pass", None, "", "after", target,
            append=True,
            blank_lines=2,
        )

        # The gap closes to two blank lines; the target's trailing blank lines
        # stay at its end.
        self.assertEqual(
            Path(source).read_text(), "def a():\n    pass\n\n\ndef b():\n    pass\n"
        )
        self.assertEqual(
            Path(target).read_text(), "x = 1\n\n\ndef moved():\n    pass\n\n\n\n"
        )
        self.assertIn("Spaced with 2 blank line(s)", output)

    def test_blank_lines_within_one_file(self) -> None:
        path = self.write(
            "a.py",
            b"def one():\n    pass\ndef two():\n    pass\n\n\n\ndef three():\n    pass\n",
        )

        _ = move_lines(
            self.store, path, None, "def three():", None, "    pass", None, "def two():", "before",
            blank_lines=1,
        )

        self.assertEqual(
            Path(path).read_text(),
            "def one():\n    pass\n\ndef three():\n    pass\n\ndef two():\n    pass\n",
        )

    def test_blank_lines_out_of_range_are_refused(self) -> None:
        path = self.write("a.py", b"def one():\n    pass\n\n\ndef two():\n    pass\n")
        with self.assertRaises(ToolError) as caught:
            _ = move_lines(
                self.store, path, None, "def two():", None, "    pass", None, "def one():", "before",
                blank_lines=11,
            )

        self.assertEqual(caught.exception.code, "E_BAD_REQUEST")

    def test_a_separator_does_not_hide_the_moved_lines_first_row(self) -> None:
        body = "".join(f"    x{number} = {number}\n" for number in range(8))
        source = self.write("a.py", f"a = 1\n\n\nclass Moved:\n{body}".encode())
        target = self.write("b.py", b"b = 2\n")

        output = move_lines(
            self.store, source, None, "class Moved:", None, "    x7 = 7", None, "", "after", target,
            append=True,
        )

        self.assertEqual(Path(target).read_text(), f"b = 2\n\n\nclass Moved:\n{body}")
        self.assertRegex(output, r"\n [a-z]{3}│b = 2\n\+[a-z]{3}│\n\+[a-z]{3}│\n\+[a-z]{3}│class Moved:\n")

    def test_moves_lines_up_and_the_moved_rows_stay_editable(self) -> None:
        path = self.write("a.txt", b"a1\nb2\nc3\nd4\n")
        anchors = anchors_by_line(read_file(self.store, path))

        _ = self.move(path, anchors, "c3", "d4", "a1", "before")
        _ = self.move(path, anchors, "d4", "d4", "b2", "after")

        self.assertEqual(Path(path).read_text(), "c3\na1\nb2\nd4\n")

    def test_moved_lines_keep_their_terminators(self) -> None:
        path = self.write("a.txt", b"a1\r\nb2\nc3")
        anchors = anchors_by_line(read_file(self.store, path))

        _ = self.move(path, anchors, "c3", "c3", "a1", "before")
        self.assertEqual(Path(path).read_bytes(), b"c3\na1\r\nb2")

        # The file still ends without a terminator, as it did before the move.
        _ = self.move(path, anchors, "a1", "a1", "b2", "after")
        self.assertEqual(Path(path).read_bytes(), b"c3\nb2\na1")

    def test_refuses_an_anchor_inside_the_range(self) -> None:
        path = self.write("a.txt", b"a1\nb2\nc3\n")
        anchors = anchors_by_line(read_file(self.store, path))

        with self.assertRaises(ToolError) as caught:
            _ = self.move(path, anchors, "a1", "c3", "b2", "after")

        self.assertEqual(caught.exception.code, "E_BAD_REQUEST")
        self.assertEqual(Path(path).read_text(), "a1\nb2\nc3\n")

    def test_a_move_to_the_same_place_changes_nothing(self) -> None:
        path = self.write("a.txt", b"a1\nb2\nc3\n")
        anchors = anchors_by_line(read_file(self.store, path))

        for target, position in [("a1", "after"), ("c3", "before")]:
            with self.subTest(target=target):
                output = self.move(path, anchors, "b2", "b2", target, position)
                self.assertEqual(output, "No change: the lines are already there.")
        self.assertEqual(Path(path).read_text(), "a1\nb2\nc3\n")

    def test_appending_a_range_that_ends_the_file_changes_nothing(self) -> None:
        path = self.write("a.txt", b"alpha\n\nbeta one\nbeta two\n\ngamma\n")

        for first, last in [("gamma", "gamma"), ("beta one", "gamma")]:
            with self.subTest(first=first):
                output = move_lines(
                    self.store, path, None, first, None, last, None, "", "after", append=True
                )
                self.assertEqual(output, "No change: the lines are already there.")
        self.assertEqual(Path(path).read_text(), "alpha\n\nbeta one\nbeta two\n\ngamma\n")

    def test_appending_a_range_that_ends_the_file_sets_its_blank_lines(self) -> None:
        path = self.write("a.txt", b"alpha\n\nbeta\n\n\n\ngamma\n")

        output = move_lines(
            self.store, path, None, "gamma", None, "gamma", None, "", "after",
            append=True,
            blank_lines=1,
        )

        self.assertEqual(Path(path).read_text(), "alpha\n\nbeta\n\ngamma\n")
        self.assertIn("Spaced with 1 blank line(s)", output)

    def test_refuses_a_range_whose_endpoint_was_not_shown(self) -> None:
        path = self.write("a.txt", b"a1\nb2\nc3\nd4\n")
        anchors = anchors_by_line(read_file(self.store, path, limit=1))
        anchors |= anchors_by_line(read_file(self.store, path, offset=4, limit=1))
        anchors["c3"] = self.store.files[Path(path).resolve()].anchors[2]

        with self.assertRaises(ToolError) as caught:
            _ = self.move(path, anchors, "a1", "c3", "d4", "after")

        self.assertEqual(caught.exception.code, "E_RANGE_UNSERVED")
        self.assertEqual(Path(path).read_text(), "a1\nb2\nc3\nd4\n")

    def test_a_separated_range_keeps_its_spacing_within_a_file(self) -> None:
        path = self.write("a.py", b"def a():\n    pass\n\n\ndef b():\n    pass\n\n\ndef c():\n    pass\n")

        output = move_lines(self.store, path, None, "def c():", None, "    pass", None, "def a():", "before")

        self.assertEqual(
            Path(path).read_text(),
            "def c():\n    pass\n\n\ndef a():\n    pass\n\n\ndef b():\n    pass\n",
        )
        self.assertIn("2 blank separator line(s) moved with them.", output)

    def test_a_separated_range_moved_to_the_end_keeps_its_spacing(self) -> None:
        path = self.write("a.py", b"def a():\n    pass\n\ndef b():\n    pass\n\ndef c():\n    pass\n")
        _ = read_file(self.store, path)
        last = self.store.files[Path(path).resolve()].anchors[-1]

        _ = move_lines(self.store, path, None, "def a():", None, "    pass", last, "    pass", "after")

        self.assertEqual(
            Path(path).read_text(), "def b():\n    pass\n\ndef c():\n    pass\n\ndef a():\n    pass\n"
        )

    def test_a_separated_range_appended_to_another_file_keeps_its_spacing(self) -> None:
        source = self.write("a.py", b"def a():\n    pass\n\n\ndef b():\n    pass\n\n\ndef c():\n    pass\n")
        target = self.write("b.py", b"import os\n")

        _ = move_lines(
            self.store, source, None, "def b():", None, "    pass", None, "import os", "after", target
        )

        self.assertEqual(Path(source).read_text(), "def a():\n    pass\n\n\ndef c():\n    pass\n")
        self.assertEqual(Path(target).read_text(), "import os\n\n\ndef b():\n    pass\n")

    def test_a_range_beside_code_moves_without_separators(self) -> None:
        path = self.write("a.txt", b"one\n\ntwo\n\nthree\nfour\n")
        anchors = anchors_by_line(read_file(self.store, path))

        _ = self.move(path, anchors, "two", "two", "three", "after")

        self.assertEqual(Path(path).read_text(), "one\n\n\nthree\ntwo\nfour\n")

    def test_moves_a_range_named_by_text_alone_without_a_read(self) -> None:
        path = self.write("a.txt", b"first line here\nblock start line\nblock end line!\nlast line here!\n")

        _ = move_lines(
            self.store,
            path,
            None,
            "block start line",
            None,
            "block end line!",
            None,
            "last line here!",
            "after",
        )

        self.assertEqual(
            Path(path).read_text(),
            "first line here\nlast line here!\nblock start line\nblock end line!\n",
        )

    def test_moves_a_range_whose_middle_was_never_shown(self) -> None:
        path = self.write("a.txt", b"a1\nb2\nc3\nd4\n")
        anchors = anchors_by_line(read_file(self.store, path, limit=1))
        anchors |= anchors_by_line(read_file(self.store, path, offset=3, limit=2))

        _ = self.move(path, anchors, "a1", "c3", "d4", "after")

        self.assertEqual(Path(path).read_text(), "d4\na1\nb2\nc3\n")

    def test_moves_lines_into_another_file(self) -> None:
        source = self.write("source.txt", b"keep\nmove1\nmove2\nkeep2\n")
        target = self.write("target.txt", b"t1\r\nt2\r\n")
        anchors = anchors_by_line(read_file(self.store, source))
        target_anchors = anchors_by_line(read_file(self.store, target))

        output = self.move(
            source, anchors, "move1", "move2", "t1", "after", target, target_anchors
        )

        self.assertEqual(Path(source).read_bytes(), b"keep\nkeep2\n")
        self.assertEqual(Path(target).read_bytes(), b"t1\r\nmove1\r\nmove2\r\nt2\r\n")
        self.assertIn(f"\n{Path(target).resolve()}\n@1\n", output)
        moved = anchors_by_line(read_file(self.store, target))
        self.assertEqual(moved["t2"], target_anchors["t2"])
        self.assertNotIn(moved["move1"], anchors.values())
        self.assertEqual(
            anchors_by_line(read_file(self.store, source))["keep2"], anchors["keep2"]
        )

    def test_a_failed_source_write_says_the_lines_are_in_both_files(self) -> None:
        source = self.write("source.txt", b"keep\nmove\n")
        target = self.write("target.txt", b"t1\n")
        anchors = anchors_by_line(read_file(self.store, source))
        target_anchors = anchors_by_line(read_file(self.store, target))
        write = refuse_writes_to(Path(source).resolve())

        with (
            mock.patch("hashline_mcp.anchors.write_text_file", write),
            self.assertRaises(ToolError) as caught,
        ):
            _ = self.move(
                source, anchors, "move", "move", "t1", "after", target, target_anchors
            )

        self.assertEqual(caught.exception.code, "E_IO")
        self.assertIn("Permission denied", caught.exception.message)
        self.assertIn("Remove them from", caught.exception.message)
        self.assertEqual(Path(source).read_bytes(), b"keep\nmove\n")
        self.assertEqual(Path(target).read_bytes(), b"t1\nmove\n")

    def test_moves_every_line_into_an_empty_file(self) -> None:
        source = self.write("source.txt", b"only\n")
        target = self.write("empty.txt", b"")
        anchors = anchors_by_line(read_file(self.store, source))
        placeholder = read_file(self.store, target).split("│")[0]

        _ = self.move(
            source, anchors, "only", "only", "", "after", target, {"": placeholder}
        )

        self.assertEqual(Path(source).read_bytes(), b"")
        self.assertEqual(Path(target).read_bytes(), b"only\n")

    def test_refuses_a_hard_link_to_the_source(self) -> None:
        path = self.write("a.txt", b"a1\nb2\n")
        link = self.root / "link.txt"
        link.hardlink_to(path)
        anchors = anchors_by_line(read_file(self.store, path))
        link_anchors = anchors_by_line(read_file(self.store, str(link)))

        with self.assertRaises(ToolError) as caught:
            _ = self.move(
                path, anchors, "a1", "a1", "b2", "after", str(link), link_anchors
            )

        self.assertEqual(caught.exception.code, "E_BAD_REQUEST")
        self.assertEqual(Path(path).read_text(), "a1\nb2\n")

    def test_to_path_naming_the_same_file_moves_within_it(self) -> None:
        path = self.write("a.txt", b"a1\nb2\n")
        anchors = anchors_by_line(read_file(self.store, path))

        output = self.move(
            path, anchors, "a1", "a1", "b2", "after", str(self.root / "." / "a.txt")
        )

        self.assertIn("they keep their anchors", output)
        self.assertEqual(Path(path).read_text(), "b2\na1\n")


if __name__ == "__main__":
    _ = unittest.main()
