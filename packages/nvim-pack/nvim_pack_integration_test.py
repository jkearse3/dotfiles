#!/usr/bin/env python3

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import final, override


configured_program = os.environ.get("NVIM_PACK_PROGRAM")
PROGRAM = (
    [configured_program]
    if configured_program is not None and configured_program != ""
    else [sys.executable, str(Path(__file__).with_name("nvim_pack.py"))]
)


@final
class NvimPackIntegrationTest(unittest.TestCase):
    temporary_directory: tempfile.TemporaryDirectory[str]
    root: Path
    config: Path
    data: Path
    state: Path

    @override
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(prefix="nvim-pack-test-")
        self.root = Path(self.temporary_directory.name)
        self.config = self.root / "config" / "nvim"
        self.data = self.root / "data"
        self.state = self.root / "state"
        self.config.mkdir(parents=True)
        self.data.mkdir()
        self.state.mkdir()

    @override
    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def create_plugin(self, relative_path: str, value: str = "1") -> Path:
        path = self.root / relative_path
        path.mkdir(parents=True)
        _ = self.run_command(["git", "init", "-q"], cwd=path)
        _ = self.run_command(
            ["git", "config", "user.email", "test@example.com"], cwd=path
        )
        _ = self.run_command(["git", "config", "user.name", "Test"], cwd=path)
        _ = (path / "plugin.lua").write_text(f"return {value}\n", encoding="utf-8")
        _ = self.run_command(["git", "add", "plugin.lua"], cwd=path)
        _ = self.run_command(["git", "commit", "-qm", f"initial {path.name}"], cwd=path)
        return path

    def environment(self, **values: str) -> dict[str, str]:
        environment = os.environ.copy()
        environment.update(
            {
                "XDG_CONFIG_HOME": str(self.config.parent),
                "XDG_DATA_HOME": str(self.data),
                "XDG_STATE_HOME": str(self.state),
            }
        )
        environment.update(values)
        return environment

    def write_config(self, plugin_variables: list[str]) -> None:
        specs = ",\n  ".join(f"{{ src = vim.env.{name} }}" for name in plugin_variables)
        _ = self.config.joinpath("init.lua").write_text(
            f"vim.pack.add({{\n  {specs},\n}}, {{ confirm = false }})\n",
            encoding="utf-8",
        )

    def run_command(
        self,
        command: list[str],
        *,
        cwd: Path | None = None,
        environment: dict[str, str] | None = None,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            cwd=cwd,
            env=environment,
            check=check,
            capture_output=True,
            text=True,
            errors="replace",
        )

    def run_nvim_pack(
        self,
        arguments: list[str],
        environment: dict[str, str],
        *,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        return self.run_command([*PROGRAM, *arguments], environment=environment, check=check)

    def test_list_check_selective_update_and_prune(self) -> None:
        alpha = self.create_plugin("alpha")
        beta = self.create_plugin("beta")
        self.write_config(["TEST_ALPHA_SRC", "TEST_BETA_SRC"])
        environment = self.environment(
            TEST_ALPHA_SRC=alpha.as_uri(),
            TEST_BETA_SRC=beta.as_uri(),
        )
        _ = self.run_command(["nvim", "--headless", "+qa"], environment=environment)
        self.assertEqual(
            self.run_nvim_pack(["list"], environment).stdout,
            "alpha\nbeta\n",
        )

        for plugin in (alpha, beta):
            _ = plugin.joinpath("plugin.lua").write_text("return 2\n", encoding="utf-8")
            _ = self.run_command(
                ["git", "commit", "-qam", f"update {plugin.name}"], cwd=plugin
            )

        checked = self.run_nvim_pack(["check", "alpha"], environment).stdout
        self.assertIn("Can update 1 plugin: alpha", checked)
        self.assertIn("update alpha", checked)

        environment["FZF_DEFAULT_OPTS"] = "--filter=alpha"
        selected = self.run_nvim_pack(["update", "--select"], environment).stdout
        self.assertIn("Updated 1 plugin: alpha", selected)
        remaining = self.run_nvim_pack(["check"], environment).stdout
        self.assertIn("Can update 1 plugin: beta", remaining)

        self.write_config(["TEST_ALPHA_SRC"])
        preview = self.run_nvim_pack(["prune", "--dry-run"], environment).stdout
        self.assertIn("Would prune 1 orphaned plugin: beta", preview)
        pruned = self.run_nvim_pack(["prune"], environment).stdout
        self.assertIn("Pruned 1 orphaned plugin: beta", pruned)
        self.assertFalse(self.data.joinpath("nvim/site/pack/core/opt/beta").exists())

    def test_check_restores_lockfile_and_origin_after_source_change(self) -> None:
        old_plugin = self.create_plugin("old/plugin", "1")
        new_plugin = self.create_plugin("new/plugin", "2")
        self.write_config(["TEST_PLUGIN_SRC"])
        old_environment = self.environment(TEST_PLUGIN_SRC=old_plugin.as_uri())
        _ = self.run_command(["nvim", "--headless", "+qa"], environment=old_environment)

        lock_path = self.config / "nvim-pack-lock.json"
        checkout = self.data / "nvim/site/pack/core/opt/plugin"
        lock_before = lock_path.read_bytes()
        origin_before = self.run_command(
            ["git", "remote", "get-url", "origin"], cwd=checkout
        ).stdout

        new_environment = self.environment(TEST_PLUGIN_SRC=new_plugin.as_uri())
        checked = self.run_nvim_pack(["check", "plugin"], new_environment).stdout
        self.assertIn("Can update 1 plugin: plugin", checked)
        self.assertEqual(lock_path.read_bytes(), lock_before)
        origin_after = self.run_command(["git", "remote", "get-url", "origin"], cwd=checkout).stdout
        self.assertEqual(origin_after, origin_before)

    def test_failed_apply_does_not_report_success(self) -> None:
        plugin = self.create_plugin("plugin")
        self.write_config(["TEST_PLUGIN_SRC"])
        environment = self.environment(TEST_PLUGIN_SRC=plugin.as_uri())
        _ = self.run_command(["nvim", "--headless", "+qa"], environment=environment)

        initial_revision = self.run_command(["git", "rev-parse", "HEAD"], cwd=plugin).stdout.strip()
        _ = plugin.joinpath(".gitmodules").write_text(
            '[submodule "bad"]\n\tpath = bad\n'
            + "\turl = file:///definitely/missing/nvim-pack-submodule\n",
            encoding="utf-8",
        )
        _ = self.run_command(["git", "add", ".gitmodules"], cwd=plugin)
        _ = self.run_command(
            ["git", "update-index", "--add", "--cacheinfo", f"160000,{initial_revision},bad"],
            cwd=plugin,
        )
        _ = self.run_command(["git", "commit", "-qm", "add broken submodule"], cwd=plugin)

        _ = self.run_nvim_pack(["check", "plugin"], environment)
        updated = self.run_nvim_pack(["update", "plugin"], environment, check=False)
        self.assertEqual(updated.returncode, 1)
        self.assertIn("plugin state may be partial", updated.stderr)
        self.assertNotIn("Updated", updated.stdout)


if __name__ == "__main__":
    _ = unittest.main()
