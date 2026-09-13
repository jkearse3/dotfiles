#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import cast


class NvimPackError(Exception):
    pass


@dataclass(frozen=True)
class ListArgs:
    pass


@dataclass(frozen=True)
class CheckArgs:
    plugins: tuple[str, ...]


@dataclass(frozen=True)
class UpdateArgs:
    plugins: tuple[str, ...]
    select: bool


@dataclass(frozen=True)
class PruneArgs:
    dry_run: bool


Args = ListArgs | CheckArgs | UpdateArgs | PruneArgs


@dataclass(frozen=True)
class UpdateReport:
    updates: list[str]
    errors: list[str]
    apply_errors: list[str]
    selection_errors: list[str]
    details: list[str]


def add_plugin_arguments(parser: argparse.ArgumentParser) -> None:
    """Add optional active-plugin selection shared by check and update."""
    _ = parser.add_argument(
        "plugins",
        nargs="*",
        metavar="PLUGIN",
        help="active plugin names to process (default: all active plugins)",
    )


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="nvim-pack",
        description="Inspect and maintain plugins managed by Neovim's vim.pack.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser(
        "list",
        help="list active plugin names",
        description="List active plugin names, one per line.",
    )
    list_parser.set_defaults(command="list")

    check_parser = subparsers.add_parser(
        "check",
        help="show available updates",
        description="Fetch and show available updates without applying them.",
    )
    add_plugin_arguments(check_parser)

    update_parser = subparsers.add_parser(
        "update",
        help="apply available updates",
        description="Apply available updates and rewrite nvim-pack-lock.json.",
    )
    add_plugin_arguments(update_parser)
    _ = update_parser.add_argument(
        "--select",
        action="store_true",
        help="choose from updatable plugins with fzf",
    )

    prune_parser = subparsers.add_parser(
        "prune",
        help="remove orphaned plugins",
        description=(
            "Remove plugins that are installed but no longer added by the current "
            "Neovim config."
        ),
    )
    _ = prune_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="list orphaned plugins without deleting them",
    )
    return parser


def parse_args(argv: list[str] | None = None) -> Args:
    namespace = create_parser().parse_args(argv)
    command = cast(str, namespace.command)
    if command == "list":
        return ListArgs()
    if command in {"check", "update"}:
        plugins = tuple(dict.fromkeys(cast(list[str], namespace.plugins)))
        if command == "check":
            return CheckArgs(plugins)
        select = cast(bool, namespace.select)
        if select and plugins:
            create_parser().error("update --select cannot be combined with plugin names")
        return UpdateArgs(
            plugins=plugins,
            select=select,
        )
    if command == "prune":
        return PruneArgs(dry_run=cast(bool, namespace.dry_run))
    raise AssertionError(f"unhandled command: {command}")


def require_nvim() -> None:
    """Fail when the host Neovim needed to load the user's config is absent."""
    if shutil.which("nvim") is None:
        raise NvimPackError(
            "nvim was not found on PATH; nvim-pack uses the host's own nvim so "
            + "the active plugin set matches this machine's config"
        )


def lua_script_path() -> Path:
    """Return the packaged Lua adapter, with a sibling fallback for source runs."""
    configured = os.environ.get("NVIM_PACK_SCRIPT")
    path = Path(configured) if configured else Path(__file__).with_suffix(".lua")
    if not path.is_file():
        raise NvimPackError(f"nvim-pack Lua adapter was not found: {path}")
    return path


def string_list(response: dict[str, object], key: str) -> list[str]:
    """Read a required string-list field from a Lua response."""
    if key not in response:
        raise NvimPackError(f"nvim-pack Lua response omitted required field {key!r}")
    value = response[key]
    if not isinstance(value, list):
        raise NvimPackError(f"nvim-pack Lua response field {key!r} was not a string list")

    strings: list[str] = []
    for item in cast(list[object], value):
        if not isinstance(item, str):
            raise NvimPackError(f"nvim-pack Lua response field {key!r} was not a string list")
        strings.append(item)
    return strings


def run_nvim(request: dict[str, object]) -> dict[str, object]:
    """Execute the Lua adapter after normal config startup and return its response."""
    with tempfile.TemporaryDirectory(prefix="nvim-pack-") as temporary_directory:
        directory = Path(temporary_directory)
        request_path = directory / "request.json"
        response_path = directory / "response.json"
        _ = request_path.write_text(json.dumps(request), encoding="utf-8")

        environment = os.environ.copy()
        environment.update(
            {
                "NVIM_PACK_REQUEST": str(request_path),
                "NVIM_PACK_RESPONSE": str(response_path),
                "NVIM_PACK_SCRIPT": str(lua_script_path()),
            }
        )
        try:
            completed = subprocess.run(
                [
                    "nvim",
                    "--headless",
                    "-c",
                    "lua dofile(vim.env.NVIM_PACK_SCRIPT)",
                    "-c",
                    "qa!",
                ],
                check=False,
                capture_output=True,
                text=True,
                errors="replace",
                env=environment,
            )
        except OSError as error:
            raise NvimPackError(f"could not run nvim: {error}") from error

        if not response_path.is_file():
            detail = completed.stderr.strip() or f"exit status {completed.returncode}"
            raise NvimPackError(f"nvim did not complete the vim.pack command: {detail}")
        try:
            response = cast(object, json.loads(response_path.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError) as error:
            raise NvimPackError(f"could not read nvim-pack Lua response: {error}") from error

    if not isinstance(response, dict):
        raise NvimPackError("nvim-pack Lua response was not an object")
    response_object = cast(dict[object, object], response)
    if not all(isinstance(key, str) for key in response_object):
        raise NvimPackError("nvim-pack Lua response had a non-string key")
    typed_response = {cast(str, key): value for key, value in response_object.items()}
    fatal_error = typed_response.get("fatal_error")
    if fatal_error is not None:
        if not isinstance(fatal_error, str):
            raise NvimPackError("nvim-pack Lua fatal_error was not a string")
        raise NvimPackError(f"nvim-pack Lua failed: {fatal_error}")
    return typed_response


def query_updates(
    apply: bool,
    plugins: Sequence[str],
    *,
    offline: bool = False,
) -> UpdateReport:
    """Return a validated update report for selected active plugins."""
    if offline and not apply:
        raise ValueError("offline mode is only valid when applying updates")
    response = run_nvim(
        {
            "apply": apply,
            "command": "update",
            "offline": offline,
            "plugins": list(plugins),
        }
    )
    report = UpdateReport(
        updates=string_list(response, "updates"),
        errors=string_list(response, "errors"),
        apply_errors=string_list(response, "apply_errors"),
        selection_errors=string_list(response, "selection_errors"),
        details=string_list(response, "details"),
    )
    if report.selection_errors:
        names = ", ".join(report.selection_errors)
        raise NvimPackError(f"not active vim.pack plugins: {names}")
    if report.errors:
        names = ", ".join(report.errors)
        raise NvimPackError(f"could not check updates for: {names}")
    if report.apply_errors:
        names = ", ".join(report.apply_errors)
        raise NvimPackError(
            f"updates did not finish cleanly for: {names}; plugin state may be partial"
        )
    return report


def select_updates(names: Sequence[str]) -> list[str]:
    """Interactively choose update candidates with fzf; cancellation is empty."""
    fzf = shutil.which("fzf")
    if fzf is None:
        raise NvimPackError("fzf was not found on PATH; update --select requires fzf")
    try:
        completed = subprocess.run(
            [
                fzf,
                "--multi",
                "--prompt=Update plugins> ",
                "--header=Tab: toggle selection | Enter: update | Esc: cancel",
            ],
            input="".join(f"{name}\n" for name in names),
            stdout=subprocess.PIPE,
            text=True,
            errors="replace",
            check=False,
        )
    except OSError as error:
        raise NvimPackError(f"could not run fzf: {error}") from error
    if completed.returncode in {1, 130}:
        return []
    if completed.returncode != 0:
        raise NvimPackError(f"fzf failed with exit status {completed.returncode}")

    allowed = set(names)
    selected = list(dict.fromkeys(completed.stdout.splitlines()))
    if any(name not in allowed for name in selected):
        raise NvimPackError("fzf returned a plugin that was not an update candidate")
    return selected


def format_update_result(names: list[str], apply: bool) -> str:
    if not names:
        return "All selected vim.pack plugins are up to date."
    noun = "plugin" if len(names) == 1 else "plugins"
    verb = "Can update" if not apply else "Updated"
    return f"{verb} {len(names)} {noun}: {', '.join(names)}"


def format_prune_result(names: list[str], dry_run: bool) -> str:
    if not names:
        return "vim.pack is in sync; no orphaned plugins to prune."
    noun = "plugin" if len(names) == 1 else "plugins"
    verb = "Would prune" if dry_run else "Pruned"
    return f"{verb} {len(names)} orphaned {noun}: {', '.join(names)}"


def run_update(
    apply: bool,
    plugins: Sequence[str],
    *,
    offline: bool = False,
) -> int:
    """Check or apply updates for selected active plugins."""
    report = query_updates(apply, plugins, offline=offline)
    print(format_update_result(report.updates, apply))
    if not apply and report.details:
        print()
        print("\n".join(report.details))
    return 0


def run_selected_update() -> int:
    """Check all plugins, select candidates with fzf, and apply from fetched refs."""
    candidates = query_updates(False, ()).updates
    if not candidates:
        print(format_update_result([], False))
        return 0

    selected = select_updates(candidates)
    if not selected:
        print("No plugins selected; nothing updated.")
        return 0
    return run_update(True, selected, offline=True)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        require_nvim()
        if isinstance(args, ListArgs):
            names = string_list(run_nvim({"command": "list"}), "names")
            if names:
                print("\n".join(names))
            return 0
        if isinstance(args, CheckArgs):
            return run_update(False, args.plugins)
        if isinstance(args, UpdateArgs):
            return run_selected_update() if args.select else run_update(True, args.plugins)
        response = run_nvim(
            {
                "command": "prune",
                "dry_run": args.dry_run,
            }
        )
        print(format_prune_result(string_list(response, "names"), args.dry_run))
        return 0
    except NvimPackError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
