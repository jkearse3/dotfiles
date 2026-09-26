"""`substitute` contracts against temporary files: guards, rewrites, anchors."""

import random
import re
import tempfile
import unittest
from pathlib import Path
from typing import override
from unittest import mock

from hashline_mcp.anchors import AnchorStore, TrackedFile
from hashline_mcp.errors import ToolError
from hashline_mcp.grep import GrepRequest, grep_files
from hashline_mcp.substitute import SubstituteRequest, substitute_lines
from hashline_mcp.text_file import Fingerprint, TextFile, decode_text, write_text_file
from hashline_mcp.tools import read_file, replace_lines

ROW = re.compile(r"^[+ ]?([a-z]{3,})│(.*)$")


def anchors_by_line(output: str) -> dict[str, str]:
    """Map line content to anchor for every row in a tool result."""
    matches = (ROW.match(line) for line in output.splitlines())
    return {match.group(2): match.group(1) for match in matches if match is not None}


class SubstituteTests(unittest.TestCase):
    @override
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.store = AnchorStore(random.Random(5))

    def write(self, name: str, data: bytes) -> str:
        path = self.root / name
        _ = path.write_bytes(data)
        return str(path)

    def assert_refused(self, code: str, request: SubstituteRequest) -> str:
        """Assert `request` is refused with `code` and leaves the file as it was."""
        before = Path(request.path).read_bytes()
        with self.assertRaises(ToolError) as caught:
            _ = substitute_lines(self.store, request)
        self.assertEqual(caught.exception.code, code)
        self.assertEqual(Path(request.path).read_bytes(), before)
        return str(caught.exception)

    def test_renames_every_matching_line_and_keeps_other_anchors(self) -> None:
        path = self.write("a.lua", b"local Entry = {}\nkeep()\nfor _, e in Entry do\n")
        before = anchors_by_line(read_file(self.store, path))

        output = substitute_lines(
            self.store, SubstituteRequest(path, r"\bEntry\b", "lib.Entry", 2)
        )

        self.assertEqual(
            Path(path).read_text(),
            "local lib.Entry = {}\nkeep()\nfor _, e in lib.Entry do\n",
        )
        self.assertRegex(
            output,
            r"^Substituted on 2 line\(s\)\. .+\n@1\n\+[a-z]{3}│local lib\.Entry = \{\}\n"
            + r"@3\n\+[a-z]{3}│for _, e in lib\.Entry do\n"
            + r"File: LF line endings, final newline\.$",
        )
        after = anchors_by_line(output)
        self.assertEqual(
            anchors_by_line(read_file(self.store, path))["keep()"], before["keep()"]
        )
        self.assertNotEqual(after["local lib.Entry = {}"], before["local Entry = {}"])

        anchor = after["local lib.Entry = {}"]
        text = "local lib.Entry = {}"
        _ = replace_lines(self.store, path, anchor, text, anchor, text, ["x"])
        self.assertEqual(Path(path).read_text().splitlines()[0], "x")

    def test_without_a_count_changes_every_match_and_refuses_none(self) -> None:
        path = self.write("a.txt", b"old one\nkeep\nold two\n")

        output = substitute_lines(self.store, SubstituteRequest(path, "old", "new"))

        self.assertEqual(Path(path).read_text(), "new one\nkeep\nnew two\n")
        self.assertTrue(output.startswith("Substituted on 2 line(s)."))
        _ = self.assert_refused("E_NO_MATCH", SubstituteRequest(path, "old", "new"))

    def test_changed_lines_retire_their_anchors(self) -> None:
        path = self.write("a.txt", b"old one\nold two\n")
        anchor = anchors_by_line(read_file(self.store, path))["old one"]
        _ = substitute_lines(self.store, SubstituteRequest(path, "old", "new", 2))

        with self.assertRaises(ToolError) as caught:
            _ = replace_lines(self.store, path, anchor, "old one", anchor, "old one", [])

        self.assertEqual(caught.exception.code, "E_STALE_ANCHOR")

    def test_count_mismatch_is_refused_with_matching_rows(self) -> None:
        path = self.write("a.txt", b"x = 1\ny = 2\nx = 3\n")

        message = self.assert_refused(
            "E_COUNT_MISMATCH", SubstituteRequest(path, "x", "z", 1)
        )
        _ = substitute_lines(self.store, SubstituteRequest(path, "x", "z", 2))

        self.assertIn("matches 2 line(s), not the expected 1", message)
        self.assertEqual(list(anchors_by_line(message)), ["x = 1", "x = 3"])
        self.assertEqual(Path(path).read_text(), "z = 1\ny = 2\nz = 3\n")

    def test_substitutes_lines_never_shown_and_shows_them(self) -> None:
        path = self.write("a.txt", b"hit\nmiss\nhit again\n")

        output = substitute_lines(self.store, SubstituteRequest(path, "hit", "done", 2))

        self.assertEqual(list(anchors_by_line(output)), ["done", "done again"])
        self.assertEqual(Path(path).read_text(), "done\nmiss\ndone again\n")

    def test_unmatched_lines_need_not_have_been_seen(self) -> None:
        path = self.write("a.txt", b"hit\nunseen\n")
        _ = read_file(self.store, path, limit=1)

        _ = substitute_lines(self.store, SubstituteRequest(path, "hit", "done", 1))

        self.assertEqual(Path(path).read_text(), "done\nunseen\n")

    def test_literal_mode_escapes_pattern_and_replacement(self) -> None:
        path = self.write("a.txt", b"a.b(c) axb\n")
        _ = read_file(self.store, path)

        _ = substitute_lines(
            self.store, SubstituteRequest(path, "a.b(c)", r"\1\n", 1, literal=True)
        )

        self.assertEqual(Path(path).read_text(), "\\1\\n axb\n")

    def test_regex_groups_and_ignore_case(self) -> None:
        path = self.write("a.txt", b"Foo(1) foo(2)\n")
        _ = read_file(self.store, path)

        _ = substitute_lines(
            self.store,
            SubstituteRequest(
                path, r"foo\((?P<n>\d)\)", r"bar[\g<n>]", 1, ignore_case=True
            ),
        )

        self.assertEqual(Path(path).read_text(), "bar[1] bar[2]\n")

    def test_range_limits_matching(self) -> None:
        path = self.write("a.txt", b"x\nstart x\nx\nend x\nx\n")
        anchors = anchors_by_line(read_file(self.store, path))

        _ = substitute_lines(
            self.store,
            SubstituteRequest(
                path,
                "x",
                "y",
                3,
                first=anchors["end x"],
                first_text="end x",
                last=anchors["start x"],
                last_text="start x",
            ),
        )

        self.assertEqual(Path(path).read_text(), "x\nstart y\ny\nend y\nx\n")

    def test_line_endings_bom_and_missing_final_newline_survive(self) -> None:
        path = self.write("a.txt", b"\xef\xbb\xbfold\r\nkeep\nold")
        _ = read_file(self.store, path)

        _ = substitute_lines(self.store, SubstituteRequest(path, "old", "new", 2))

        self.assertEqual(Path(path).read_bytes(), b"\xef\xbb\xbfnew\r\nkeep\nnew")

    def test_substitution_into_an_empty_file_ends_the_line(self) -> None:
        path = self.write("a.txt", b"")
        _ = read_file(self.store, path)

        _ = substitute_lines(self.store, SubstituteRequest(path, "^$", "x = 1", 1))

        self.assertEqual(Path(path).read_bytes(), b"x = 1\n")
        tracked = self.store.files[Path(path).resolve()]
        self.assertEqual(tracked.content.endings, ["\n"])

    def test_emptying_an_unterminated_last_line_ends_it(self) -> None:
        path = self.write("a.txt", b"a\nx")
        _ = read_file(self.store, path)

        _ = substitute_lines(self.store, SubstituteRequest(path, "x", "", 1))

        self.assertEqual(Path(path).read_bytes(), b"a\n\n")
        tracked = self.store.files[Path(path).resolve()]
        self.assertEqual(tracked.content, decode_text(b"a\n\n", Path(path)))
        self.assertEqual(len(tracked.anchors), 2)

    def test_unchanged_result_does_not_write(self) -> None:
        path = self.write("a.txt", b"same\n")
        _ = read_file(self.store, path)
        version = Path(path).stat().st_mtime_ns

        output = substitute_lines(self.store, SubstituteRequest(path, "same", "same", 1))

        self.assertTrue(output.startswith("No change"))
        self.assertEqual(Path(path).stat().st_mtime_ns, version)

    def test_bad_requests_are_refused_before_writing(self) -> None:
        path = self.write("a.txt", b"a\nb\n")
        anchor = anchors_by_line(read_file(self.store, path))["a"]

        for request in (
            SubstituteRequest(path, "", "x", 1),
            SubstituteRequest(path, "a", "x", 0),
            SubstituteRequest(path, "(", "x", 1),
            SubstituteRequest(path, "a", r"\2", 1),
            SubstituteRequest(path, "a", "x\ny", 1),
            SubstituteRequest(path, "a", "x\r", 1),
            SubstituteRequest(path, "a", "nul\0", 1),
            SubstituteRequest(path, "a", "\ud800", 1),
            SubstituteRequest(path, "a", "x", 1, first=anchor, first_text="a"),
        ):
            with self.subTest(request=request):
                _ = self.assert_refused("E_BAD_REQUEST", request)


class DirectorySubstituteTests(unittest.TestCase):
    @override
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.store = AnchorStore(random.Random(9))
        _ = (self.root / "a.py").write_text("old = 1\nkeep = 2\n")
        (self.root / "sub").mkdir()
        _ = (self.root / "sub" / "b.py").write_text("use(old)\n")
        _ = (self.root / "sub" / "c.txt").write_text("old text\n")
        _ = (self.root / "none.py").write_text("nothing here\n")

    def request(self, count: int, **options: object) -> SubstituteRequest:
        glob = options.get("glob")
        return SubstituteRequest(
            str(self.root),
            r"\bold\b",
            "new",
            count,
            glob=glob if isinstance(glob, str) else None,
        )

    def grep(self, pattern: str) -> str:
        return grep_files(self.store, GrepRequest(pattern, path=str(self.root)))

    def test_substitutes_in_every_file_under_a_directory(self) -> None:
        _ = self.grep("old")

        output = substitute_lines(self.store, self.request(3))

        self.assertEqual((self.root / "a.py").read_text(), "new = 1\nkeep = 2\n")
        self.assertEqual((self.root / "sub" / "b.py").read_text(), "use(new)\n")
        self.assertEqual((self.root / "sub" / "c.txt").read_text(), "new text\n")
        self.assertRegex(
            output,
            r"^Substituted on 3 line\(s\) in 3 file\(s\)\.\n.*a\.py\n@1\n\+[a-z]{3}│new = 1\n"
            + r"File: LF line endings, final newline\.\n"
            + r".*b\.py\n@1\n\+[a-z]{3}│use\(new\)\nFile: .*\n"
            + r".*c\.txt\n@1\n\+[a-z]{3}│new text\nFile: LF line endings, final newline\.$",
        )
        self.assertNotIn((self.root / "none.py").resolve(), self.store.files)

    def test_glob_limits_the_files(self) -> None:
        _ = self.grep("old")

        _ = substitute_lines(self.store, self.request(2, glob="*.py"))

        self.assertEqual((self.root / "sub" / "c.txt").read_text(), "old text\n")
        self.assertEqual((self.root / "sub" / "b.py").read_text(), "use(new)\n")

    def test_a_catch_all_glob_leaves_vcs_directories_out(self) -> None:
        for directory in (".git", ".jj"):
            (self.root / directory).mkdir()
            _ = (self.root / directory / "config").write_text("old\n")
        _ = self.grep("old")
        for directory in (".git", ".jj"):
            _ = read_file(self.store, str(self.root / directory / "config"))

        _ = substitute_lines(self.store, self.request(3, glob="*"))

        self.assertEqual((self.root / ".git" / "config").read_text(), "old\n")
        self.assertEqual((self.root / ".jj" / "config").read_text(), "old\n")

    def test_a_hard_linked_file_is_counted_and_rewritten_once(self) -> None:
        (self.root / "sub" / "b-link.py").hardlink_to(self.root / "sub" / "b.py")
        _ = self.grep("old")

        output = substitute_lines(self.store, self.request(3))

        # Like every write here, the rewrite replaces the file, so the link splits.
        self.assertIn("in 3 file(s)", output)
        self.assertEqual((self.root / "sub" / "b-link.py").read_text(), "use(new)\n")

    def test_ignored_and_binary_files_are_skipped(self) -> None:
        _ = (self.root / ".ignore").write_text("sub/\n")
        _ = (self.root / "blob.bin").write_bytes(b"old\0\n")
        _ = self.grep("old")

        _ = substitute_lines(self.store, self.request(1))

        self.assertEqual((self.root / "a.py").read_text(), "new = 1\nkeep = 2\n")
        self.assertEqual((self.root / "sub" / "b.py").read_text(), "use(old)\n")

    def test_count_mismatch_lists_matching_rows_by_file(self) -> None:
        with self.assertRaises(ToolError) as caught:
            _ = substitute_lines(self.store, self.request(2))

        message = str(caught.exception)
        self.assertEqual(caught.exception.code, "E_COUNT_MISMATCH")
        self.assertIn("matches 3 line(s), not the expected 2", message)
        self.assertRegex(message, r"\n.*a\.py\n@1\n[a-z]{3}│old = 1\n.*b\.py\n")
        self.assertEqual((self.root / "a.py").read_text(), "old = 1\nkeep = 2\n")

    def test_substitutes_across_files_never_shown(self) -> None:
        output = substitute_lines(self.store, self.request(3))

        self.assertIn("Substituted on 3 line(s) in 3 file(s).", output)
        self.assertEqual((self.root / "sub" / "b.py").read_text(), "use(new)\n")

    def test_file_only_and_directory_only_options_are_refused(self) -> None:
        _ = self.grep("old")
        a_py = str(self.root / "a.py")

        for request in (
            SubstituteRequest(a_py, "old", "new", 1, glob="*.py"),
            SubstituteRequest(
                str(self.root), "old", "new", 3, first="abc", first_text="x"
            ),
        ):
            with self.subTest(request=request), self.assertRaises(ToolError) as caught:
                _ = substitute_lines(self.store, request)
            self.assertEqual(caught.exception.code, "E_BAD_REQUEST")

    def test_a_failed_later_write_names_the_files_already_written(self) -> None:
        _ = self.grep("old")
        commit_rewrite = self.store.commit_rewrite
        calls: list[Path] = []

        def fail_second(tracked: TrackedFile, changes: dict[int, str]) -> TrackedFile:
            calls.append(tracked.path)
            if len(calls) == 2:
                raise ToolError("E_FILE_CHANGED", "changed on disk")
            return commit_rewrite(tracked, changes)

        with (
            mock.patch.object(self.store, "commit_rewrite", fail_second),
            self.assertRaises(ToolError) as caught,
        ):
            _ = substitute_lines(self.store, self.request(3))

        self.assertEqual(caught.exception.code, "E_FILE_CHANGED")
        self.assertIn(f"already rewritten: {calls[0]}.", str(caught.exception))

    def test_a_later_write_failing_with_os_error_names_the_files_already_written(
        self,
    ) -> None:
        _ = self.grep("old")
        calls: list[Path] = []

        def refuse_second(path: Path, content: TextFile, expected: Fingerprint) -> Fingerprint:
            calls.append(path)
            if len(calls) == 2:
                raise PermissionError(13, "Permission denied", str(path))
            return write_text_file(path, content, expected)

        with (
            mock.patch("hashline_mcp.anchors.write_text_file", refuse_second),
            self.assertRaises(ToolError) as caught,
        ):
            _ = substitute_lines(self.store, self.request(3))

        self.assertEqual(caught.exception.code, "E_IO")
        self.assertIn("Permission denied", caught.exception.message)
        self.assertIn(f"already rewritten: {calls[0]}.", caught.exception.message)
        self.assertIn("new", calls[0].read_text())
        self.assertIn("old", calls[1].read_text())

    def test_a_first_write_failing_with_os_error_propagates_unchanged(self) -> None:
        _ = self.grep("old")

        def refuse(path: Path, content: TextFile, expected: Fingerprint) -> Fingerprint:
            raise PermissionError(13, "Permission denied", str(path))

        with (
            mock.patch("hashline_mcp.anchors.write_text_file", refuse),
            self.assertRaises(PermissionError),
        ):
            _ = substitute_lines(self.store, self.request(3))

        self.assertEqual((self.root / "a.py").read_text(), "old = 1\nkeep = 2\n")


if __name__ == "__main__":
    _ = unittest.main()
