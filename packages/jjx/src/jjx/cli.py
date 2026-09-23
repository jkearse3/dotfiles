"""Dispatch the jjx command hierarchy directly to Python command handlers."""

from __future__ import annotations

import sys
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Protocol, TextIO

from .commands import bookmark_backup, bookmark_land, bookmark_queries
from .commands import description_format, ensure, interactive, worktree_add


class CommandHandler(Protocol):
    """A jjx leaf handler that reports completion with an integer exit status."""

    def __call__(self, arguments: Sequence[str], *, prog: str) -> int:
        """Run one leaf command using PROG in help and diagnostics."""
        ...


@dataclass(frozen=True)
class Command:
    """Describe one jjx leaf command and its in-process handler."""

    path: tuple[str, ...]
    description: str
    handler: CommandHandler

    @classmethod
    def define(
        cls,
        path: str,
        description: str,
        handler: CommandHandler,
    ) -> Command:
        """Create a command from its space-delimited public PATH."""
        return cls(tuple(path.split()), description, handler)

    @property
    def prog(self) -> str:
        """Return the complete program name shown by this leaf."""
        return "jjx " + " ".join(self.path)

    def run(self, arguments: Sequence[str]) -> int:
        """Run this command with its canonical program name."""
        return self.handler(arguments, prog=self.prog)


COMMANDS = (
    Command.define(
        "bookmark backup",
        "Preserve remote bookmark history locally",
        bookmark_backup.main,
    ),
    Command.define(
        "bookmark current",
        "Print the nearest current bookmark",
        bookmark_queries.current_main,
    ),
    Command.define(
        "bookmark default",
        "Print the trunk bookmark",
        bookmark_queries.default_main,
    ),
    Command.define(
        "bookmark land",
        "Land a linear bookmark stack",
        bookmark_land.main,
    ),
    Command.define(
        "bookmark nearest",
        "Query nearest matching bookmarks",
        bookmark_queries.nearest_main,
    ),
    Command.define(
        "bookmark previous",
        "Print the previous stacked bookmark",
        bookmark_queries.previous_main,
    ),
    Command.define(
        "bookmark push",
        "Interactively push bookmarks",
        interactive.bookmark_push,
    ),
    Command.define(
        "bookmark rebase",
        "Interactively rebase bookmarks",
        interactive.bookmark_rebase,
    ),
    Command.define(
        "bookmark select",
        "Interactively select a bookmark",
        interactive.bookmark_select,
    ),
    Command.define(
        "bookmark stacked",
        "List bookmarks from the current change to trunk",
        bookmark_queries.stacked_main,
    ),
    Command.define(
        "change select",
        "Interactively select a change",
        interactive.change_select,
    ),
    Command.define(
        "description format",
        "Format a revision description",
        description_format.main,
    ),
    Command.define(
        "ensure",
        "Ensure a Git checkout has compatible jj state",
        ensure.main,
    ),
    Command.define(
        "worktree add",
        "Create a detached Git worktree with independent jj state",
        worktree_add.main,
    ),
)


def main(arguments: Sequence[str] | None = None) -> int:
    """Dispatch ARGUMENTS to a jjx leaf command and return its exit status."""
    argv = list(sys.argv[1:] if arguments is None else arguments)
    command, leaf_arguments = _resolve_command(argv)
    if command is None:
        return _show_help_or_error(argv)
    return command.run(leaf_arguments)


def _resolve_command(arguments: list[str]) -> tuple[Command | None, list[str]]:
    """Resolve the longest command path at the start of ARGUMENTS."""
    for command in sorted(COMMANDS, key=lambda item: len(item.path), reverse=True):
        path_length = len(command.path)
        if tuple(arguments[:path_length]) == command.path:
            return command, arguments[path_length:]
    return None, arguments


def _show_help_or_error(arguments: list[str]) -> int:
    """Print relevant command help, reporting unknown paths as usage errors."""
    if len(arguments) == 0 or arguments in (["-h"], ["--help"]):
        _print_help()
        return 0
    if len(arguments) in {1, 2} and arguments[-1] in {"-h", "--help"}:
        group = arguments[0]
        if any(command.path[0] == group for command in COMMANDS):
            _print_help(group)
            return 0
    if len(arguments) == 1 and any(
        command.path[0] == arguments[0] for command in COMMANDS
    ):
        _print_help(arguments[0])
        return 0

    print(f"jjx: unknown command: {' '.join(arguments)}", file=sys.stderr)
    _print_help(file=sys.stderr)
    return 2


def _print_help(group: str | None = None, *, file: TextIO | None = None) -> None:
    """Print root or group command help to FILE, defaulting to standard output."""
    output = sys.stdout if file is None else file
    if group is None:
        print("usage: jjx <command> [<args>]", file=output)
        print("\nAdditional commands for Jujutsu workflows.\n", file=output)
        print("commands:", file=output)
        groups = {command.path[0] for command in COMMANDS}
        for name in sorted(groups):
            direct = next(
                (command for command in COMMANDS if command.path == (name,)), None
            )
            description = (
                direct.description if direct is not None else f"Commands for {name}s"
            )
            print(f"  {name:<12} {description}", file=output)
        print("\nRun 'jjx <command> --help' for more information.", file=output)
        return

    print(f"usage: jjx {group} <command> [<args>]", file=output)
    print(f"\n{group} commands:\n", file=output)
    for command in COMMANDS:
        if command.path[0] == group:
            print(
                f"  {' '.join(command.path[1:]):<12} {command.description}", file=output
            )
