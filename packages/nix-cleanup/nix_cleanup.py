#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import cast


SYSTEM_PROFILE = Path("/nix/var/nix/profiles/system")
GC_ROOTS = Path("/nix/var/nix/gcroots")


class CleanupError(Exception):
    pass


@dataclass(frozen=True)
class Profiles:
    user: Path
    home_manager: Path
    system: Path = SYSTEM_PROFILE


@dataclass(frozen=True)
class Args:
    command: str | None
    older_than: int | None


def non_negative_int(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a non-negative integer") from error
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be a non-negative integer")
    return parsed


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="nix-cleanup",
        description=(
            "Inspect and safely remove old Nix profile generations and store paths."
        ),
        epilog=(
            "Report and preview commands do not request deletion. Nix GC inspection "
            "may still prune stale auto-GC-root symlinks."
        ),
    )
    subparsers = parser.add_subparsers(dest="command", metavar="COMMAND")
    _ = subparsers.add_parser(
        "report",
        help="report disk usage, generations, development roots, and open paths",
    )

    commands = {
        "preview": "preview user/Home Manager history deletion and store GC",
        "clean": "delete user/Home Manager history, then garbage-collect the store",
        "system-preview": "preview nix-darwin/NixOS system generation deletion",
        "system-clean": (
            "delete system generation history with sudo, then run store GC"
        ),
    }
    for name, help_text in commands.items():
        command_parser = subparsers.add_parser(name, help=help_text)
        _ = command_parser.add_argument(
            "--older-than",
            type=non_negative_int,
            metavar="DAYS",
            help="retain generations newer than DAYS instead of all history",
        )
    _ = subparsers.add_parser("help", help="show this help message")
    return parser


def parse_args(argv: list[str] | None = None) -> tuple[argparse.ArgumentParser, Args]:
    parser = create_parser()
    namespace = parser.parse_args(argv)
    return parser, Args(
        command=cast(str | None, namespace.command),
        older_than=cast(int | None, getattr(namespace, "older_than", None)),
    )


def profiles() -> Profiles:
    state_home = os.environ.get("NIX_STATE_HOME")
    if not state_home:
        state_home = os.environ.get("XDG_STATE_HOME") or str(
            Path.home() / ".local" / "state"
        )
        state_home = str(Path(state_home) / "nix")
    profiles_dir = Path(state_home) / "profiles"
    return Profiles(
        user=profiles_dir / "profile",
        home_manager=profiles_dir / "home-manager",
    )


def profile_exists(profile: Path) -> bool:
    return profile.exists() or profile.is_symlink()


def generation_count(profile: Path) -> int:
    if not profile.parent.is_dir():
        return 0
    return sum(
        generation.is_symlink()
        for generation in profile.parent.glob(f"{profile.name}-[0-9]*-link")
    )


def report_profile(label: str, profile: Path) -> None:
    if not profile_exists(profile):
        print(f"{label + ':':14} missing ({profile})")
        return
    try:
        current = profile.readlink().name
    except OSError:
        current = "unknown"
    print(f"{label + ':':14} {generation_count(profile)} generations; current {current}")


def report_development_roots(root_dir: Path = GC_ROOTS) -> None:
    roots: list[tuple[Path, str]] = []
    if root_dir.is_dir():
        for directory, directory_names, file_names in os.walk(root_dir):
            for name in [*directory_names, *file_names]:
                root = Path(directory) / name
                if not root.is_symlink():
                    continue
                try:
                    target = os.readlink(root)
                except OSError:
                    target = ""
                roots.append((root, target))

    development = [item for item in roots if ".direnv" in f"{item[0]} {item[1]}"]
    print(f"Direct GC-root links: {len(roots)} ({len(development)} direnv roots)")
    for root, target in development[:10]:
        print(f"  {root} -> {target}")
    if len(development) > 10:
        print(f"  ... and {len(development) - 10} more direnv roots")


def report_open_paths() -> None:
    try:
        process = subprocess.Popen(
            ["lsof", "-nP", "-Fpcn"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            errors="replace",
        )
        output, _ = process.communicate()
    except OSError:
        print("Open files: unavailable (lsof failed)")
        return
    if process.returncode != 0:
        print("Open files: unavailable (lsof failed)")
        return

    paths: set[str] = set()
    processes: set[tuple[str, str]] = set()
    pid = ""
    command = ""
    for line in output.splitlines():
        if line.startswith("p"):
            pid = line[1:]
            command = ""
        elif line.startswith("c"):
            command = line[1:]
        elif line.startswith("n/nix/store/") and pid not in {
            str(os.getpid()),
            str(process.pid),
        }:
            parts = line[1:].split("/", 4)
            if len(parts) >= 4:
                paths.add(f"/nix/store/{parts[3]}")
                processes.add((pid, command))

    print(
        f"Open files: {len(paths)} store paths held open by "
        + f"{len(processes)} processes visible to this user"
    )
    for open_pid, open_command in sorted(processes)[:10]:
        print(f"  PID {open_pid}: {open_command}")


def volume_usage(path: str = "/nix") -> tuple[int, int, int]:
    usage = shutil.disk_usage(path)
    return usage.total, usage.used, usage.free


def format_bytes(value: int) -> str:
    amount = float(value)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB", "PiB"):
        if abs(amount) < 1024 or unit == "PiB":
            return f"{amount:.1f} {unit}" if unit != "B" else f"{int(amount)} B"
        amount /= 1024
    raise AssertionError("unreachable")


def report(selected_profiles: Profiles) -> None:
    print("Nix volume:")
    try:
        total, used, free = volume_usage()
        print(
            f"  total {format_bytes(total)}; used {format_bytes(used)}; "
            + f"available {format_bytes(free)}"
        )
    except OSError:
        print("warning: /nix is unavailable", file=sys.stderr)
    print("\nProfiles:")
    report_profile("User", selected_profiles.user)
    report_profile("Home Manager", selected_profiles.home_manager)
    report_profile("System", selected_profiles.system)
    print("\nRetaining roots:")
    report_development_roots()
    report_open_paths()


def run_command(arguments: list[str]) -> bool:
    try:
        return subprocess.run(arguments, check=False).returncode == 0
    except OSError as error:
        raise CleanupError(f"could not run {arguments[0]}: {error}") from error


def retention(older_than: int | None) -> str | None:
    return f"{older_than}d" if older_than is not None else None


def wipe_profile(
    mode: str, label: str, profile: Path, older_than: int | None
) -> bool:
    if not profile_exists(profile):
        print(f"Skipping missing {label} profile: {profile}")
        return True

    arguments = ["nix", "profile", "wipe-history", "--profile", str(profile)]
    retained = retention(older_than)
    if retained is not None:
        arguments.extend(["--older-than", retained])
    if mode == "preview":
        arguments.append("--dry-run")

    print(
        f"\n{mode.capitalize()} {label} profile history "
        + f"({generation_count(profile)} generations):"
    )
    return run_command(arguments)


def preview_store_gc() -> bool:
    print("\nStore GC preview under current roots:")
    print(
        "Profile previews do not remove roots, so this cannot estimate the "
        + "combined reclaimed space."
    )
    print("Nix may prune stale auto-GC-root symlinks while inspecting roots.")
    return run_command(["nix", "store", "gc", "--dry-run"])


def preview_user_cleanup(selected_profiles: Profiles, older_than: int | None) -> None:
    report(selected_profiles)
    if not wipe_profile("preview", "user", selected_profiles.user, older_than):
        raise CleanupError("user profile cleanup preview failed")
    if not wipe_profile(
        "preview", "Home Manager", selected_profiles.home_manager, older_than
    ):
        raise CleanupError("Home Manager cleanup preview failed")
    if not preview_store_gc():
        raise CleanupError("store GC preview failed")


def report_reclaimed(before: int, after: int) -> None:
    difference = before - after
    if difference >= 0:
        print(f"\nReclaimed according to volume usage: {format_bytes(difference)}\n")
    else:
        print(
            "\nVolume usage increased during cleanup by: "
            + f"{format_bytes(-difference)}\n"
        )


def clean_user_profiles(selected_profiles: Profiles, older_than: int | None) -> None:
    report(selected_profiles)
    print("\nCleanup plan:")
    if not wipe_profile("preview", "user", selected_profiles.user, older_than):
        raise CleanupError("user profile cleanup preview failed; nothing was deleted")
    if not wipe_profile(
        "preview", "Home Manager", selected_profiles.home_manager, older_than
    ):
        raise CleanupError("Home Manager cleanup preview failed; nothing was deleted")
    if not preview_store_gc():
        raise CleanupError("store GC preview failed; nothing was deleted")

    print("\nDeleting the profile generations listed above, then running store GC.")
    before = volume_usage()[1]
    if not wipe_profile("clean", "user", selected_profiles.user, older_than):
        raise CleanupError(
            "user profile cleanup failed; Home Manager history and store GC were not run"
        )
    if not wipe_profile(
        "clean", "Home Manager", selected_profiles.home_manager, older_than
    ):
        raise CleanupError(
            "Home Manager cleanup failed after user profile cleanup; store GC was not run"
        )
    if not run_command(["nix", "store", "gc"]):
        raise CleanupError(
            "store GC failed after profile histories were cleaned; rerun nix store gc"
        )
    report_reclaimed(before, volume_usage()[1])
    report(selected_profiles)


def system_generation_argument(older_than: int | None) -> str:
    retained = retention(older_than)
    return retained if retained is not None else "old"


def preview_system_cleanup(selected_profiles: Profiles, older_than: int | None) -> None:
    profile = selected_profiles.system
    if not profile_exists(profile):
        print(f"System profile is not present: {profile}")
        return
    report_profile("System", profile)
    print("\nPreview system generation cleanup; no sudo is used:")
    if not run_command(
        [
            "nix-env",
            "--profile",
            str(profile),
            "--delete-generations",
            system_generation_argument(older_than),
            "--dry-run",
        ]
    ):
        raise CleanupError("system generation cleanup preview failed")


def clean_system_profile(selected_profiles: Profiles, older_than: int | None) -> None:
    profile = selected_profiles.system
    if not profile_exists(profile):
        print(f"System profile is not present: {profile}")
        return
    if shutil.which("sudo") is None:
        raise CleanupError("sudo is required for system generation cleanup")

    preview_system_cleanup(selected_profiles, older_than)
    print(
        "\nDeleting the system generations listed above with sudo, then running store GC."
    )
    before = volume_usage()[1]
    if not run_command(
        [
            "sudo",
            "nix-env",
            "--profile",
            str(profile),
            "--delete-generations",
            system_generation_argument(older_than),
        ]
    ):
        raise CleanupError("system generation cleanup failed; store GC was not run")
    if not run_command(["nix", "store", "gc"]):
        raise CleanupError(
            "store GC failed after system generations were cleaned; rerun nix store gc"
        )
    report_reclaimed(before, volume_usage()[1])
    report(selected_profiles)


def main(argv: list[str] | None = None) -> int:
    parser, args = parse_args(argv)
    if args.command in {None, "help"}:
        parser.print_help()
        return 0

    selected_profiles = profiles()
    try:
        if args.command == "report":
            report(selected_profiles)
        elif args.command == "preview":
            preview_user_cleanup(selected_profiles, args.older_than)
        elif args.command == "clean":
            clean_user_profiles(selected_profiles, args.older_than)
        elif args.command == "system-preview":
            preview_system_cleanup(selected_profiles, args.older_than)
        elif args.command == "system-clean":
            clean_system_profile(selected_profiles, args.older_than)
        else:
            raise AssertionError(f"unhandled command: {args.command}")
    except CleanupError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
