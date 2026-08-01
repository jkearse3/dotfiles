#!/usr/bin/env python3
# pyright: reportImplicitRelativeImport=false, reportUninitializedInstanceVariable=false

from __future__ import annotations

import io
import os
import shutil
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final, override
from unittest.mock import patch

import nix_cleanup


@final
class NixCleanupTest(unittest.TestCase):
    temporary_directory: TemporaryDirectory[str]
    root: Path
    user: Path
    home_manager: Path
    system: Path
    profiles: nix_cleanup.Profiles

    @override
    def setUp(self) -> None:
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.user = self.root / "profile"
        self.home_manager = self.root / "home-manager"
        self.system = self.root / "system"
        for profile in (self.user, self.home_manager, self.system):
            target = profile.with_suffix(".target")
            target.touch()
            profile.symlink_to(target)
        self.profiles = nix_cleanup.Profiles(
            user=self.user,
            home_manager=self.home_manager,
            system=self.system,
        )

    def test_profile_environment_precedence(self) -> None:
        home = self.root / "home"
        cases = (
            (
                {
                    "HOME": str(home),
                    "NIX_STATE_HOME": str(self.root / "nix-state"),
                    "XDG_STATE_HOME": str(self.root / "xdg-state"),
                },
                self.root / "nix-state/profiles/profile",
            ),
            (
                {"HOME": str(home), "XDG_STATE_HOME": str(self.root / "xdg-state")},
                self.root / "xdg-state/nix/profiles/profile",
            ),
            (
                {
                    "HOME": str(home),
                    "NIX_STATE_HOME": "",
                    "XDG_STATE_HOME": "",
                },
                home / ".local/state/nix/profiles/profile",
            ),
            (
                {"HOME": str(home)},
                home / ".local/state/nix/profiles/profile",
            ),
        )
        for environment, expected in cases:
            with self.subTest(environment=environment):
                with patch.dict(os.environ, environment, clear=True):
                    selected = nix_cleanup.profiles()
                self.assertEqual(selected.user, expected)

    def test_argparse_validates_retention(self) -> None:
        _, args = nix_cleanup.parse_args(["preview", "--older-than", "30"])
        self.assertEqual(args.older_than, 30)
        with self.assertRaises(SystemExit):
            _ = nix_cleanup.parse_args(["preview", "--older-than", "-1"])

    def test_preview_command_order(self) -> None:
        calls: list[list[str]] = []

        def record(arguments: list[str]) -> bool:
            calls.append(arguments)
            return True

        with (
            patch.object(nix_cleanup, "report"),
            patch.object(nix_cleanup, "run_command", side_effect=record),
        ):
            nix_cleanup.preview_user_cleanup(self.profiles, 30)
        self.assertEqual(
            calls,
            [
                [
                    "nix",
                    "profile",
                    "wipe-history",
                    "--profile",
                    str(self.user),
                    "--older-than",
                    "30d",
                    "--dry-run",
                ],
                [
                    "nix",
                    "profile",
                    "wipe-history",
                    "--profile",
                    str(self.home_manager),
                    "--older-than",
                    "30d",
                    "--dry-run",
                ],
                ["nix", "store", "gc", "--dry-run"],
            ],
        )

    def test_user_cleanup_never_uses_sudo(self) -> None:
        calls: list[list[str]] = []

        def record(arguments: list[str]) -> bool:
            calls.append(arguments)
            return True

        with (
            patch.object(nix_cleanup, "report"),
            patch.object(nix_cleanup, "volume_usage", return_value=(200, 100, 100)),
            patch.object(nix_cleanup, "run_command", side_effect=record),
        ):
            nix_cleanup.clean_user_profiles(self.profiles, 30)
        self.assertEqual(
            calls,
            [
                [
                    "nix",
                    "profile",
                    "wipe-history",
                    "--profile",
                    str(self.user),
                    "--older-than",
                    "30d",
                    "--dry-run",
                ],
                [
                    "nix",
                    "profile",
                    "wipe-history",
                    "--profile",
                    str(self.home_manager),
                    "--older-than",
                    "30d",
                    "--dry-run",
                ],
                ["nix", "store", "gc", "--dry-run"],
                [
                    "nix",
                    "profile",
                    "wipe-history",
                    "--profile",
                    str(self.user),
                    "--older-than",
                    "30d",
                ],
                [
                    "nix",
                    "profile",
                    "wipe-history",
                    "--profile",
                    str(self.home_manager),
                    "--older-than",
                    "30d",
                ],
                ["nix", "store", "gc"],
            ],
        )
        self.assertFalse(any(call[0] == "sudo" for call in calls))

    def test_preview_failure_prevents_deletion(self) -> None:
        for failing_call in range(3):
            calls: list[list[str]] = []

            def run_command(arguments: list[str]) -> bool:
                calls.append(arguments)
                return len(calls) != failing_call + 1

            with self.subTest(failing_call=failing_call):
                with (
                    patch.object(nix_cleanup, "report"),
                    patch.object(nix_cleanup, "run_command", side_effect=run_command),
                ):
                    with self.assertRaises(nix_cleanup.CleanupError):
                        nix_cleanup.clean_user_profiles(self.profiles, None)
                self.assertEqual(len(calls), failing_call + 1)
                self.assertTrue(all("--dry-run" in call for call in calls))

    def test_system_cleanup_limits_sudo_to_nix_env(self) -> None:
        calls: list[list[str]] = []

        def record(arguments: list[str]) -> bool:
            calls.append(arguments)
            return True

        with (
            patch.object(nix_cleanup, "report"),
            patch.object(nix_cleanup, "report_profile"),
            patch.object(nix_cleanup, "volume_usage", return_value=(200, 100, 100)),
            patch.object(shutil, "which", return_value="/usr/bin/sudo"),
            patch.object(nix_cleanup, "run_command", side_effect=record),
        ):
            nix_cleanup.clean_system_profile(self.profiles, 30)
        self.assertEqual(
            calls,
            [
                [
                    "nix-env",
                    "--profile",
                    str(self.system),
                    "--delete-generations",
                    "30d",
                    "--dry-run",
                ],
                [
                    "sudo",
                    "nix-env",
                    "--profile",
                    str(self.system),
                    "--delete-generations",
                    "30d",
                ],
                ["nix", "store", "gc"],
            ],
        )

    def test_partial_cleanup_stops_before_gc(self) -> None:
        calls: list[list[str]] = []

        def run_command(arguments: list[str]) -> bool:
            calls.append(arguments)
            return not (
                arguments[:3] == ["nix", "profile", "wipe-history"]
                and str(self.home_manager) in arguments
                and "--dry-run" not in arguments
            )

        with (
            patch.object(nix_cleanup, "report"),
            patch.object(nix_cleanup, "volume_usage", return_value=(200, 100, 100)),
            patch.object(nix_cleanup, "run_command", side_effect=run_command),
        ):
            with self.assertRaisesRegex(
                nix_cleanup.CleanupError, "failed after user profile cleanup"
            ):
                nix_cleanup.clean_user_profiles(self.profiles, None)
        self.assertNotIn(["nix", "store", "gc"], calls)

    def test_report_runs_without_nix_on_path(self) -> None:
        with (
            patch.object(nix_cleanup, "profiles", return_value=self.profiles),
            patch.object(nix_cleanup, "report") as reported,
            patch.object(shutil, "which", return_value=None),
        ):
            self.assertEqual(nix_cleanup.main(["report"]), 0)
        reported.assert_called_once()

    def test_missing_nix_fails_before_any_command_runs(self) -> None:
        for command in ("preview", "clean", "system-preview", "system-clean"):
            with self.subTest(command=command):
                errors = io.StringIO()
                with (
                    patch.object(nix_cleanup, "profiles", return_value=self.profiles),
                    patch.object(shutil, "which", return_value=None),
                    patch.object(nix_cleanup, "run_command") as run_command,
                    patch.object(sys, "stderr", errors),
                ):
                    self.assertEqual(nix_cleanup.main([command]), 1)
                run_command.assert_not_called()
                self.assertIn("nix was not found on PATH", errors.getvalue())


if __name__ == "__main__":
    _ = unittest.main(argv=[sys.argv[0]])
