#!/usr/bin/env python3
# pyright: reportAny=false, reportImplicitRelativeImport=false, reportPrivateLocalImportUsage=false, reportUnknownArgumentType=false, reportUnusedCallResult=false

from __future__ import annotations

import io
import json
import os
import shutil
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import final
from unittest.mock import patch

import nvim_pack


@final
class NvimPackTest(unittest.TestCase):
    def test_parse_args_supports_all_commands(self) -> None:
        self.assertEqual(nvim_pack.parse_args(["list"]), nvim_pack.ListArgs())
        self.assertEqual(
            nvim_pack.parse_args(["check", "a.nvim", "a.nvim"]),
            nvim_pack.CheckArgs(("a.nvim",)),
        )
        self.assertEqual(
            nvim_pack.parse_args(["update", "a.nvim", "b.nvim"]),
            nvim_pack.UpdateArgs(("a.nvim", "b.nvim"), select=False),
        )
        self.assertEqual(
            nvim_pack.parse_args(["update", "--select"]),
            nvim_pack.UpdateArgs((), select=True),
        )
        self.assertEqual(
            nvim_pack.parse_args(["prune", "--dry-run"]),
            nvim_pack.PruneArgs(dry_run=True),
        )

    def test_parse_args_rejects_select_with_plugin_names(self) -> None:
        with (
            patch.object(sys, "stderr", io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            _ = nvim_pack.parse_args(["update", "--select", "a.nvim"])

    def test_lua_script_path_uses_environment_or_source_sibling(self) -> None:
        configured = Path(__file__)
        with patch.dict(os.environ, {"NVIM_PACK_SCRIPT": str(configured)}):
            self.assertEqual(nvim_pack.lua_script_path(), configured)
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(nvim_pack.lua_script_path(), Path(__file__).with_name("nvim_pack.lua"))

    def test_run_nvim_uses_json_files_and_fixed_lua_command(self) -> None:
        request: dict[str, object] = {"command": "list"}
        captured_command: list[str] = []

        def run(command: list[str], **kwargs: object) -> SimpleNamespace:
            captured_command.extend(command)
            environment = kwargs["env"]
            assert isinstance(environment, dict)
            request_path = Path(environment["NVIM_PACK_REQUEST"])
            response_path = Path(environment["NVIM_PACK_RESPONSE"])
            self.assertEqual(json.loads(request_path.read_text()), request)
            response_path.write_text('{"names":["a.nvim"]}', encoding="utf-8")
            return SimpleNamespace(returncode=0, stdout="plugin chatter", stderr="")

        with patch.object(nvim_pack.subprocess, "run", side_effect=run):
            self.assertEqual(nvim_pack.run_nvim(request), {"names": ["a.nvim"]})
        self.assertIn("lua dofile(vim.env.NVIM_PACK_SCRIPT)", captured_command)
        self.assertNotIn(json.dumps(request), captured_command)

    def test_run_nvim_requires_a_response_file(self) -> None:
        completed = SimpleNamespace(returncode=0, stdout="", stderr="Lua failed")
        with patch.object(nvim_pack.subprocess, "run", return_value=completed):
            with self.assertRaisesRegex(nvim_pack.NvimPackError, "did not complete"):
                _ = nvim_pack.run_nvim({"command": "list"})

    def test_run_nvim_surfaces_lua_fatal_error(self) -> None:
        def run(_command: list[str], **kwargs: object) -> SimpleNamespace:
            environment = kwargs["env"]
            assert isinstance(environment, dict)
            Path(environment["NVIM_PACK_RESPONSE"]).write_text(
                '{"fatal_error":"broken adapter"}', encoding="utf-8"
            )
            return SimpleNamespace(returncode=0, stdout="", stderr="")

        with patch.object(nvim_pack.subprocess, "run", side_effect=run):
            with self.assertRaisesRegex(nvim_pack.NvimPackError, "broken adapter"):
                _ = nvim_pack.run_nvim({"command": "list"})

    def test_query_updates_sends_structured_request(self) -> None:
        response: dict[str, object] = {
            "updates": ["a.nvim"],
            "errors": [],
            "apply_errors": [],
            "selection_errors": [],
            "details": ["## a.nvim", "Revision after: def"],
        }
        with patch.object(nvim_pack, "run_nvim", return_value=response) as run:
            report = nvim_pack.query_updates(True, ["a.nvim"], offline=True)
        self.assertEqual(report.updates, ["a.nvim"])
        self.assertEqual(
            run.call_args.args[0],
            {
                "apply": True,
                "command": "update",
                "offline": True,
                "plugins": ["a.nvim"],
            },
        )

    def test_query_updates_rejects_selection_and_apply_failures(self) -> None:
        base: dict[str, object] = {
            "updates": [],
            "errors": [],
            "apply_errors": [],
            "selection_errors": ["missing.nvim"],
            "details": [],
        }
        with patch.object(nvim_pack, "run_nvim", return_value=base):
            with self.assertRaisesRegex(nvim_pack.NvimPackError, "not active"):
                _ = nvim_pack.query_updates(True, ["missing.nvim"])

        base["selection_errors"] = []
        base["apply_errors"] = ["partial.nvim"]
        with patch.object(nvim_pack, "run_nvim", return_value=base):
            with self.assertRaisesRegex(nvim_pack.NvimPackError, "state may be partial"):
                _ = nvim_pack.query_updates(True, ["partial.nvim"])

    def test_string_list_rejects_missing_or_malformed_lua_response(self) -> None:
        with self.assertRaisesRegex(nvim_pack.NvimPackError, "omitted required field"):
            _ = nvim_pack.string_list({}, "names")
        with self.assertRaisesRegex(nvim_pack.NvimPackError, "was not a string list"):
            _ = nvim_pack.string_list({"names": "a.nvim"}, "names")

    def test_select_updates_runs_fzf_in_multi_select_mode(self) -> None:
        completed = SimpleNamespace(stdout="b.nvim\na.nvim\n", returncode=0)
        with (
            patch.object(shutil, "which", return_value="/bin/fzf"),
            patch.object(nvim_pack.subprocess, "run", return_value=completed) as run,
        ):
            self.assertEqual(
                nvim_pack.select_updates(["a.nvim", "b.nvim"]),
                ["b.nvim", "a.nvim"],
            )
        self.assertIn("--multi", run.call_args.args[0])
        self.assertEqual(run.call_args.kwargs["input"], "a.nvim\nb.nvim\n")

    def test_select_updates_treats_fzf_cancel_as_empty(self) -> None:
        completed = SimpleNamespace(stdout="", returncode=130)
        with (
            patch.object(shutil, "which", return_value="/bin/fzf"),
            patch.object(nvim_pack.subprocess, "run", return_value=completed),
        ):
            self.assertEqual(nvim_pack.select_updates(["a.nvim"]), [])

    def test_selected_update_applies_only_choice_from_fetched_refs(self) -> None:
        checked = nvim_pack.UpdateReport(
            updates=["a.nvim", "b.nvim"],
            errors=[],
            apply_errors=[],
            selection_errors=[],
            details=[],
        )
        applied = nvim_pack.UpdateReport(
            updates=["b.nvim"],
            errors=[],
            apply_errors=[],
            selection_errors=[],
            details=[],
        )
        output = io.StringIO()
        with (
            patch.object(nvim_pack, "query_updates", side_effect=[checked, applied]) as query,
            patch.object(nvim_pack, "select_updates", return_value=["b.nvim"]),
            patch.object(sys, "stdout", output),
        ):
            self.assertEqual(nvim_pack.run_selected_update(), 0)
        self.assertEqual(query.call_args_list[0].args, (False, ()))
        self.assertEqual(query.call_args_list[1].args, (True, ["b.nvim"]))
        self.assertTrue(query.call_args_list[1].kwargs["offline"])
        self.assertIn("Updated 1 plugin: b.nvim", output.getvalue())

    def test_main_lists_plugins_for_completion_and_fzf(self) -> None:
        output = io.StringIO()
        with (
            patch.object(shutil, "which", return_value="/usr/bin/nvim"),
            patch.object(nvim_pack, "run_nvim", return_value={"names": ["a.nvim", "b.nvim"]}),
            patch.object(sys, "stdout", output),
        ):
            self.assertEqual(nvim_pack.main(["list"]), 0)
        self.assertEqual(output.getvalue(), "a.nvim\nb.nvim\n")

    def test_main_check_reports_update_details(self) -> None:
        response: dict[str, object] = {
            "updates": ["foo.nvim"],
            "errors": [],
            "apply_errors": [],
            "selection_errors": [],
            "details": ["## foo.nvim", "Revision before: abc", "Revision after: def"],
        }
        output = io.StringIO()
        with (
            patch.object(shutil, "which", return_value="/usr/bin/nvim"),
            patch.object(nvim_pack, "run_nvim", return_value=response),
            patch.object(sys, "stdout", output),
        ):
            self.assertEqual(nvim_pack.main(["check", "foo.nvim"]), 0)
        rendered = output.getvalue()
        self.assertIn("Can update 1 plugin: foo.nvim", rendered)
        self.assertIn("Revision before: abc", rendered)

    def test_main_prune_reports_orphans(self) -> None:
        output = io.StringIO()
        with (
            patch.object(shutil, "which", return_value="/usr/bin/nvim"),
            patch.object(nvim_pack, "run_nvim", return_value={"names": ["old.nvim"]}) as run,
            patch.object(sys, "stdout", output),
        ):
            self.assertEqual(nvim_pack.main(["prune", "--dry-run"]), 0)
        self.assertEqual(
            run.call_args.args[0],
            {
                "command": "prune",
                "dry_run": True,
            },
        )
        self.assertIn("Would prune 1 orphaned plugin: old.nvim", output.getvalue())

    def test_missing_nvim_fails_before_command(self) -> None:
        errors = io.StringIO()
        with (
            patch.object(shutil, "which", return_value=None),
            patch.object(nvim_pack, "run_nvim") as run_nvim,
            patch.object(sys, "stderr", errors),
        ):
            self.assertEqual(nvim_pack.main(["list"]), 1)
        run_nvim.assert_not_called()
        self.assertIn("nvim was not found on PATH", errors.getvalue())


if __name__ == "__main__":
    _ = unittest.main(argv=[sys.argv[0]])
