#!/usr/bin/env python3

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from dataclasses import dataclass
from typing import cast


# Boundary between the Lua query and this CLI: nvim's stdout also carries
# unrelated plugin/integration chatter, so only `PRUNE\t`-prefixed lines are read
# as plugin names, and a lone `PRUNE-DONE` line marks a query that ran to
# completion (see `run_nvim`).
PRUNE_MARKER = "PRUNE\t"
COMPLETION_MARKER = "PRUNE-DONE"


class PruneError(Exception):
    pass


@dataclass(frozen=True)
class Args:
    dry_run: bool


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="nvim-pack-prune",
        description=(
            "Delete vim.pack plugins the current Neovim config no longer adds, "
            "reconciling installed plugin directories and nvim-pack-lock.json "
            "with init.lua."
        ),
        epilog=(
            "Orphans accumulate when a plugin block is disabled or removed: the "
            "install directory and lock entry persist even though init.lua no "
            "longer calls vim.pack.add for it."
        ),
    )
    _ = parser.add_argument(
        "--dry-run",
        action="store_true",
        help="list orphaned plugins without deleting anything",
    )
    return parser


def parse_args(argv: list[str] | None = None) -> Args:
    namespace = create_parser().parse_args(argv)
    return Args(dry_run=cast(bool, namespace.dry_run))


def build_lua(dry_run: bool) -> str:
    """Return the `-c` Ex command that reports and (unless dry-run) deletes orphans.

    Run by `nvim --headless -c`, which executes an *Ex* command, not Lua, and
    treats embedded newlines as separate (failing) commands — so the whole chunk
    stays on one line behind a `lua ` prefix. `--headless` still sources
    init.lua, so `plugin.active` reflects whether it added the plugin this
    session; `active == false` marks an orphan. Deletion runs before the
    `PRUNE\\t<name>` lines are emitted, so reported names are ones actually
    removed, and the trailing `PRUNE-DONE` line lets `run_nvim` distinguish a
    completed query from an nvim aborted mid-command (which still exits 0).
    """
    delete = "" if dry_run else "if #orphans > 0 then vim.pack.del(orphans) end "
    return (
        "lua "
        "local orphans = {} "
        "for _, plugin in ipairs(vim.pack.get()) do "
        "if plugin.active == false then orphans[#orphans + 1] = plugin.spec.name end "
        "end "
        + delete
        + "for _, name in ipairs(orphans) do io.stdout:write('PRUNE\\t' .. name .. '\\n') end "
        "io.stdout:write('PRUNE-DONE\\n')"
    )


def parse_pruned(stdout: str) -> list[str]:
    names: list[str] = []
    for line in stdout.splitlines():
        if line.startswith(PRUNE_MARKER):
            name = line[len(PRUNE_MARKER) :]
            if name:
                names.append(name)
    return names


def format_result(names: list[str], dry_run: bool) -> str:
    if not names:
        return "vim.pack is in sync; no orphaned plugins to prune."
    noun = "plugin" if len(names) == 1 else "plugins"
    verb = "Would prune" if dry_run else "Pruned"
    return f"{verb} {len(names)} orphaned {noun}: {', '.join(names)}"


def require_nvim() -> None:
    """Fail before querying if no `nvim` is on PATH.

    `nvim` is resolved from PATH rather than pinned at build time so the plugin
    `active` set reflects this host's own config, not a fixed neovim's.
    """
    if shutil.which("nvim") is None:
        raise PruneError(
            "nvim was not found on PATH; nvim-pack-prune uses the host's own "
            "nvim so the active plugin set matches this machine's config"
        )


def run_nvim(lua: str) -> str:
    try:
        completed = subprocess.run(
            ["nvim", "--headless", "-c", lua, "-c", "qa"],
            check=False,
            capture_output=True,
            text=True,
            errors="replace",
        )
    except OSError as error:
        raise PruneError(f"could not run nvim: {error}") from error
    # nvim exits 0 even when a `-c` command errors out, so the completion marker,
    # not the exit code, is the reliable signal that the query actually ran.
    if COMPLETION_MARKER not in completed.stdout.splitlines():
        detail = completed.stderr.strip() or f"exit status {completed.returncode}"
        raise PruneError(f"nvim did not complete the vim.pack query: {detail}")
    return completed.stdout


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        require_nvim()
        names = parse_pruned(run_nvim(build_lua(args.dry_run)))
    except PruneError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(format_result(names, args.dry_run))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
