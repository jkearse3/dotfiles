from __future__ import annotations

import subprocess
import unittest
from typing import cast, final
from unittest.mock import call, patch

from jjx.commands import bookmark_queries


@final
class BookmarkQueryTests(unittest.TestCase):
    """Preserve bookmark-query ordering, cleanup, and fallback behavior."""

    def test_nearest_preserves_exact_names_and_ignores_blank_records(self) -> None:
        result = subprocess.CompletedProcess([], 0, '"trail*"\n\n"main"\n', "")
        with patch("subprocess.run", return_value=result) as run:
            self.assertEqual(["trail*", "main"], bookmark_queries.nearest("trunk()"))
        command = cast(list[str], run.call_args.args[0])
        self.assertIn(
            'local_bookmarks.map(|b| json(b.name())).join("\\n") ++ if(local_bookmarks, "\\n")',
            command,
        )

    def test_current_prefers_descendants_before_ancestors(self) -> None:
        with patch.object(bookmark_queries, "nearest", side_effect=[[], ["base"]]) as nearest:
            self.assertEqual("base", bookmark_queries.current())
        self.assertEqual(
            [
                call("roots(@:: & bookmarks())"),
                call("heads(::@ & bookmarks())"),
            ],
            nearest.call_args_list,
        )

    def test_current_rejects_multiple_nearest_bookmarks(self) -> None:
        with (
            patch.object(bookmark_queries, "nearest", return_value=["one", "two"]),
            self.assertRaisesRegex(bookmark_queries.BookmarkQueryError, "multiple descendant"),
        ):
            _ = bookmark_queries.current()

    def test_stacked_appends_trunk_and_previous_uses_second_entry(self) -> None:
        result = subprocess.CompletedProcess([], 0, '"topic"\n"base"\n', "")
        with (
            patch.object(bookmark_queries, "default", return_value="main"),
            patch("subprocess.run", return_value=result),
        ):
            self.assertEqual(["topic", "base", "main"], bookmark_queries.stacked())
        with patch.object(
            bookmark_queries,
            "_stack_entries",
            return_value=[("topic",), ("base",), ("main",)],
        ):
            self.assertEqual("base", bookmark_queries.previous())

    def test_previous_preserves_commas_inside_one_bookmark_name(self) -> None:
        result = subprocess.CompletedProcess([], 0, '"topic"\n"release,1"\n', "")
        with (
            patch.object(bookmark_queries, "default", return_value="main"),
            patch("subprocess.run", return_value=result),
        ):
            self.assertEqual("release,1", bookmark_queries.previous())

    def test_previous_rejects_multiple_bookmarks_on_one_revision(self) -> None:
        result = subprocess.CompletedProcess([], 0, '"topic"\n"base"\t"alias"\n', "")
        with (
            patch.object(bookmark_queries, "default", return_value="main"),
            patch("subprocess.run", return_value=result),
            self.assertRaisesRegex(bookmark_queries.BookmarkQueryError, "base\\nalias"),
        ):
            _ = bookmark_queries.previous()

    def test_stacked_does_not_append_trunk_already_present_in_an_entry(self) -> None:
        result = subprocess.CompletedProcess([], 0, '"topic"\n"main"\t"alias"\n', "")
        with (
            patch.object(bookmark_queries, "default", return_value="main"),
            patch("subprocess.run", return_value=result),
        ):
            self.assertEqual(["topic", "main,alias"], bookmark_queries.stacked())
