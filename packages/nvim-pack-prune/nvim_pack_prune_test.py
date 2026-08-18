#!/usr/bin/env python3
# pyright: reportImplicitRelativeImport=false

from __future__ import annotations

import io
import shutil
import sys
import unittest
from typing import final
from unittest.mock import patch

import nvim_pack_prune


@final
class NvimPackPruneTest(unittest.TestCase):
    def test_build_lua_queries_and_marks_orphans(self) -> None:
        for dry_run in (True, False):
            with self.subTest(dry_run=dry_run):
                lua = nvim_pack_prune.build_lua(dry_run)
                self.assertIn("vim.pack.get()", lua)
                self.assertIn("plugin.active == false", lua)
                self.assertIn("PRUNE\\t", lua)
                self.assertIn("PRUNE-DONE", lua)

    def test_build_lua_is_single_lua_command(self) -> None:
        # `nvim -c` runs an Ex command; a `lua ` prefix and no newlines are what
        # make it execute as Lua rather than error out per line.
        for dry_run in (True, False):
            with self.subTest(dry_run=dry_run):
                lua = nvim_pack_prune.build_lua(dry_run)
                self.assertTrue(lua.startswith("lua "))
                self.assertNotIn("\n", lua)

    def test_build_lua_deletes_only_when_not_dry_run(self) -> None:
        self.assertIn("vim.pack.del(orphans)", nvim_pack_prune.build_lua(False))
        self.assertNotIn("vim.pack.del", nvim_pack_prune.build_lua(True))

    def test_build_lua_deletes_before_reporting(self) -> None:
        # Names are emitted only after deletion, so a report reflects plugins
        # actually removed rather than merely enumerated.
        lua = nvim_pack_prune.build_lua(False)
        self.assertLess(lua.index("vim.pack.del(orphans)"), lua.index("io.stdout:write"))

    def test_parse_pruned_reads_only_marker_lines(self) -> None:
        stdout = (
            "[integration] some unrelated chatter\n"
            "PRUNE\tcopilot.lua\n"
            "not a plugin name\n"
            "PRUNE\told-plugin.nvim\n"
            "PRUNE\t\n"  # empty name is ignored
        )
        self.assertEqual(
            nvim_pack_prune.parse_pruned(stdout),
            ["copilot.lua", "old-plugin.nvim"],
        )

    def test_parse_pruned_empty_stdout(self) -> None:
        self.assertEqual(nvim_pack_prune.parse_pruned(""), [])

    def test_format_result_in_sync(self) -> None:
        for dry_run in (True, False):
            with self.subTest(dry_run=dry_run):
                message = nvim_pack_prune.format_result([], dry_run)
                self.assertIn("in sync", message)

    def test_format_result_singular_and_plural(self) -> None:
        self.assertEqual(
            nvim_pack_prune.format_result(["a.nvim"], False),
            "Pruned 1 orphaned plugin: a.nvim",
        )
        self.assertEqual(
            nvim_pack_prune.format_result(["a.nvim", "b.nvim"], False),
            "Pruned 2 orphaned plugins: a.nvim, b.nvim",
        )

    def test_format_result_dry_run_wording(self) -> None:
        self.assertEqual(
            nvim_pack_prune.format_result(["a.nvim"], True),
            "Would prune 1 orphaned plugin: a.nvim",
        )

    def test_main_reports_and_returns_zero(self) -> None:
        output = io.StringIO()
        with (
            patch.object(shutil, "which", return_value="/usr/bin/nvim"),
            patch.object(
                nvim_pack_prune,
                "run_nvim",
                return_value="noise\nPRUNE\tfoo.nvim\nPRUNE-DONE\n",
            ),
            patch.object(sys, "stdout", output),
        ):
            self.assertEqual(nvim_pack_prune.main([]), 0)
        self.assertIn("Pruned 1 orphaned plugin: foo.nvim", output.getvalue())

    def test_run_nvim_requires_completion_marker(self) -> None:
        def completed(stdout: str, stderr: str = "", returncode: int = 0) -> object:
            return type(
                "Completed",
                (),
                {"stdout": stdout, "stderr": stderr, "returncode": returncode},
            )()

        with patch.object(
            nvim_pack_prune.subprocess,
            "run",
            return_value=completed("chatter\nPRUNE\ta.nvim\nPRUNE-DONE\n"),
        ):
            self.assertEqual(
                nvim_pack_prune.run_nvim("lua ..."),
                "chatter\nPRUNE\ta.nvim\nPRUNE-DONE\n",
            )

        # nvim swallows `-c` errors and still exits 0; a missing marker must
        # surface as an error instead of a silent empty (false "in sync") result.
        with patch.object(
            nvim_pack_prune.subprocess,
            "run",
            return_value=completed("", stderr="E492: Not an editor command"),
        ):
            with self.assertRaisesRegex(nvim_pack_prune.PruneError, "did not complete"):
                _ = nvim_pack_prune.run_nvim("lua ...")

    def test_run_nvim_missing_binary_raises(self) -> None:
        with patch.object(
            nvim_pack_prune.subprocess, "run", side_effect=OSError("no nvim")
        ):
            with self.assertRaisesRegex(nvim_pack_prune.PruneError, "could not run nvim"):
                _ = nvim_pack_prune.run_nvim("lua ...")

    def test_main_dry_run_passes_non_deleting_lua(self) -> None:
        captured: list[str] = []

        def record(lua: str) -> str:
            captured.append(lua)
            return ""

        with (
            patch.object(shutil, "which", return_value="/usr/bin/nvim"),
            patch.object(nvim_pack_prune, "run_nvim", side_effect=record),
        ):
            self.assertEqual(nvim_pack_prune.main(["--dry-run"]), 0)
        self.assertEqual(len(captured), 1)
        self.assertNotIn("vim.pack.del", captured[0])

    def test_missing_nvim_fails_before_query(self) -> None:
        errors = io.StringIO()
        with (
            patch.object(shutil, "which", return_value=None),
            patch.object(nvim_pack_prune, "run_nvim") as run_nvim,
            patch.object(sys, "stderr", errors),
        ):
            self.assertEqual(nvim_pack_prune.main([]), 1)
        run_nvim.assert_not_called()
        self.assertIn("nvim was not found on PATH", errors.getvalue())


if __name__ == "__main__":
    _ = unittest.main(argv=[sys.argv[0]])
