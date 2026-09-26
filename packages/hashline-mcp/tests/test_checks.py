"""The file report that ends every edit result."""

import random
import tempfile
import unittest
from pathlib import Path
from typing import override

from hashline_mcp.anchors import AnchorStore
from hashline_mcp.checks import file_report


class FileReportTests(unittest.TestCase):
    @override
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.store = AnchorStore(random.Random(5))

    def report(self, name: str, data: bytes) -> str:
        path = self.root / name
        _ = path.write_bytes(data)
        return file_report(self.store.sync(path.resolve()))

    def test_reports_terminators_and_bom(self) -> None:
        cases = [
            ("a.txt", b"a\nb\n", "File: LF line endings, final newline."),
            ("b.txt", b"a\r\nb", "File: CRLF line endings, no final newline."),
            (
                "c.txt",
                b"\xef\xbb\xbfa\r\nb\n",
                "File: mixed line endings (1 CRLF, 1 LF), final newline, UTF-8 BOM.",
            ),
        ]
        for name, data, expected in cases:
            with self.subTest(name=name):
                self.assertEqual(self.report(name, data), expected)

    def test_reports_every_file_type_alike(self) -> None:
        # Source files get the same report as any text, parseable or not.
        for name in ("a.md", "ok.py", "bad.py", "bad.json", "bad.toml"):
            with self.subTest(name=name):
                self.assertEqual(
                    self.report(name, b"def f(:\n"), "File: LF line endings, final newline."
                )


if __name__ == "__main__":
    _ = unittest.main()
