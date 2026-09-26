"""`grep` contracts against temporary trees; requires ripgrep on PATH."""

import json
import os
import random
import tempfile
import unittest
from pathlib import Path
from typing import override
from unittest import mock

from hashline_mcp.anchors import AnchorStore
from hashline_mcp.errors import ToolError
from hashline_mcp.grep import GrepRequest, grep_files
from hashline_mcp.tools import read_file, replace_lines


class GrepTests(unittest.TestCase):
    @override
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.store = AnchorStore(random.Random(3))
        previous = Path.cwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, previous)

    def write(self, name: str, text: str) -> Path:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        _ = path.write_text(text)
        return path

    def test_hits_are_editable_without_read(self) -> None:
        path = self.write("src/a.py", "one\ntarget = 1\nthree\n")

        output = grep_files(self.store, GrepRequest(pattern="target"))
        anchor = output.splitlines()[2].split("│")[0]
        _ = replace_lines(
            self.store,
            str(path),
            anchor,
            "target = 1",
            anchor,
            "target = 1",
            ["target = 2"],
        )

        self.assertEqual(output.splitlines()[:2], ["src/a.py", "@2"])
        self.assertEqual(path.read_text(), "one\ntarget = 2\nthree\n")

    def test_count_reports_matching_lines_without_rows(self) -> None:
        path = self.write("a.txt", "hit\nhit hit\nmiss\n")
        _ = self.write("sub/b.txt", "hit\n")

        output = grep_files(self.store, GrepRequest(pattern="hit", count=True, limit=1))

        self.assertEqual(
            output.splitlines(),
            ["a.txt: 2", "sub/b.txt: 1", "Total: 3 matching line(s) in 2 file(s)."]
            if output.startswith("a.txt")
            else ["sub/b.txt: 1", "a.txt: 2", "Total: 3 matching line(s) in 2 file(s)."],
        )
        self.assertEqual(self.store.sync(path).served, set())
        with self.assertRaises(ToolError):
            _ = grep_files(self.store, GrepRequest(pattern="hit", count=True, context=1))

    def test_markers_give_only_the_line_whatever_the_file_type(self) -> None:
        text = "class Box:\n    def open(self):\n        return hit\n"
        for name in ("a.py", "a.txt"):
            _ = self.write(name, text)
            output = grep_files(self.store, GrepRequest(pattern="hit", path=name))
            with self.subTest(name=name):
                self.assertEqual(output.splitlines()[1], "@3")

    def test_anchors_match_read_and_context_groups_runs(self) -> None:
        path = self.write("a.txt", "a\nhit\nb\nc\nd\nhit\ne\n")
        read_rows = read_file(self.store, str(path)).splitlines()

        output = grep_files(self.store, GrepRequest(pattern="hit", context=1))

        self.assertEqual(
            output.splitlines(),
            ["a.txt", "@1", *read_rows[0:3], "@5", *read_rows[4:7]],
        )

    def test_limit_drops_context_of_unshown_matches(self) -> None:
        path = self.write("a.txt", "hit1\na\nb\nc\nd\ne\nx\ny\nhit2\n")
        read_rows = read_file(self.store, str(path)).splitlines()

        output = grep_files(
            self.store, GrepRequest(pattern="hit", path="a.txt", context=2, limit=1)
        )

        self.assertEqual(
            output.splitlines(),
            [
                "a.txt",
                "@1",
                *read_rows[0:3],
                "[Stopped at 1 matches; narrow the pattern or path, or give `count: true` for complete counts.]",
            ],
        )

    def test_size_limit_serves_the_rows_that_fit(self) -> None:
        path = self.write("a.txt", "".join(f"match {'x' * 1500}\n" for _ in range(100)))

        output = grep_files(self.store, GrepRequest(pattern="match", path="a.txt"))
        lines = output.splitlines()
        shown = len(lines) - 3
        tracked = self.store.sync(path)

        self.assertEqual(lines[:2], ["a.txt", "@1"])
        self.assertEqual(
            lines[-1], "[Output cut at the size limit; narrow the pattern or path.]"
        )
        self.assertTrue(0 < shown < 100)
        self.assertLessEqual(len(output), 60_000 + len(lines[-1]) + 1)
        self.assertEqual(
            [anchor in tracked.served for anchor in tracked.anchors],
            [index < shown for index in range(100)],
        )

    def test_limit_glob_literal_and_ignore_case(self) -> None:
        _ = self.write("a.py", "x.y\nX.Y\nx.y\n")
        _ = self.write("b.txt", "x.y\n")

        output = grep_files(
            self.store,
            GrepRequest(
                pattern="x.y", glob="*.py", literal=True, ignore_case=True, limit=2
            ),
        )

        self.assertNotIn("b.txt", output)
        self.assertEqual(sum(1 for line in output.splitlines() if "│" in line), 2)
        self.assertIn("[Stopped at 2 matches", output)

    def test_no_matches_binary_and_git_are_skipped(self) -> None:
        _ = self.write(".git/config", "needle\n")
        _ = (self.root / "blob.bin").write_bytes(b"needle\0")

        output = grep_files(self.store, GrepRequest(pattern="needle"))

        self.assertEqual(output, "No matches.")

    def test_invalid_requests_are_refused(self) -> None:
        for request in (
            GrepRequest(pattern="("),
            GrepRequest(pattern=""),
            GrepRequest(pattern="x", context=99),
        ):
            with self.subTest(request=request), self.assertRaises(ToolError) as caught:
                _ = grep_files(self.store, request)
            self.assertEqual(caught.exception.code, "E_BAD_REQUEST")

    def fake_ripgrep(self, script: str) -> None:
        """Put an `rg` running `script` first on PATH for this test."""
        bin_directory = self.root / "fake-bin"
        bin_directory.mkdir()
        fake = bin_directory / "rg"
        _ = fake.write_text("#!/bin/sh\n" + script)
        fake.chmod(0o755)
        _ = self.enterContext(
            mock.patch.dict(
                os.environ, {"PATH": f"{bin_directory}{os.pathsep}{os.environ['PATH']}"}
            )
        )

    def test_heavy_stderr_does_not_block_the_search(self) -> None:
        path = self.write("a.txt", "needle\n")
        event = json.dumps(
            {
                "type": "match",
                "data": {"path": {"text": str(path)}, "line_number": 1},
            }
        )
        self.fake_ripgrep(
            f"head -c 300000 /dev/zero | tr '\\0' e >&2\necho '{event}'\n"
        )

        output = grep_files(self.store, GrepRequest(pattern="needle"))

        self.assertIn("│needle", output)

    def test_timeout_keeps_hits_before_a_cut_line(self) -> None:
        path = self.write("a.txt", "needle\n")
        event = json.dumps(
            {
                "type": "match",
                "data": {"path": {"text": str(path)}, "line_number": 1},
            }
        )
        self.fake_ripgrep(f"echo '{event}'\nprintf '{{\"type\":\"ma'\nexec sleep 60\n")

        # The deadline covers starting the fake and its first output, which a
        # loaded machine can delay by more than a fraction of a second.
        with mock.patch("hashline_mcp.grep.RIPGREP_TIMEOUT_SECONDS", 2):
            output = grep_files(self.store, GrepRequest(pattern="needle"))

        self.assertIn("│needle", output)
        self.assertIn("results are partial", output)

    def test_slow_search_times_out(self) -> None:
        self.fake_ripgrep("exec sleep 5\n")

        with (
            mock.patch("hashline_mcp.grep.RIPGREP_TIMEOUT_SECONDS", 0.2),
            self.assertRaises(ToolError) as caught,
        ):
            _ = grep_files(self.store, GrepRequest(pattern="x"))

        self.assertEqual(caught.exception.code, "E_GREP_FAILED")


if __name__ == "__main__":
    _ = unittest.main()
