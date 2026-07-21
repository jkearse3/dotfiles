from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import cast

from .commands import WorktreeError, add, attach, init, remove
from .commands import list as list_command
from .commands import path as path_command


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="jj-worktree",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=(
            "Manage detached Git worktrees with independent colocated jj histories. "
            "Worktrees live under the physical primary's .jj-worktrees directory."
        ),
        epilog=(
            "init installs or repairs Git and jj ignore rules for /.jj-worktrees/. "
            "add defaults to the exact local NAME bookmark; -r selects exactly one revision. "
            "attach initializes independent jj state in an externally owned linked Git "
            "worktree and never manages its lifecycle. Attachment and later mutating jj "
            "commands may detach its Git HEAD or rewrite its Git index. "
            "Each worktree has an independent jj operation and undo history. Exchange work "
            "explicitly with uniquely named bookmarks backed by shared Git refs; anonymous "
            "Git-backed commits may also become visible without moving another working copy. "
            "The private-Git-directory initialization is an unsupported jj compatibility "
            "dependency that must be retested on upgrades. "
            "remove requires clean Git state, an empty undescribed jj working copy, and --yes. "
            "WARNING: git clean -fdx can delete /.jj-worktrees/.\n"
            "Exclude it with: git clean -fdx -e '/.jj-worktrees/'"
        ),
    )
    subparsers = parser.add_subparsers(dest="command", metavar="COMMAND")
    _ = subparsers.add_parser("init", help="install or repair managed-root exclusion")
    add_parser = subparsers.add_parser("add", help="create a detached managed worktree")
    _ = add_parser.add_argument("name", metavar="NAME")
    _ = add_parser.add_argument("-r", "--revision", help="one revision instead of bookmark NAME")
    attach_parser = subparsers.add_parser(
        "attach",
        help="initialize jj in an externally owned linked worktree",
        description=(
            "Initialize independent jj state in an externally owned linked Git worktree. "
            "This command never manages its lifecycle."
        ),
        epilog=(
            "This uses an unsupported jj compatibility dependency: private-Git-directory "
            "initialization. Attachment and later mutating jj commands may detach its Git "
            "HEAD or rewrite its Git index."
        ),
    )
    _ = attach_parser.add_argument("path", metavar="PATH", nargs="?", default=".")
    path_parser = subparsers.add_parser("path", help="print a recorded managed worktree path")
    _ = path_parser.add_argument("name", metavar="NAME")
    listing = subparsers.add_parser("list", help="list recorded managed worktrees")
    _ = listing.add_argument("names", metavar="NAME", nargs="*")
    remove_parser = subparsers.add_parser("remove", help="remove a clean managed worktree")
    _ = remove_parser.add_argument("name", metavar="NAME")
    _ = remove_parser.add_argument("--yes", action="store_true", help="confirm destructive removal")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = create_parser()
    namespace = parser.parse_args(argv)
    command = cast(str | None, namespace.command)
    if command is None:
        parser.print_help()
        return 0
    try:
        if command == "init":
            _ = init.initialize()
        elif command == "add":
            print(add.add_worktree(cast(str, namespace.name), cast(str | None, namespace.revision)))
        elif command == "attach":
            print(attach.attach_worktree(Path(cast(str, namespace.path))))
        elif command == "path":
            print(path_command.worktree_path(cast(str, namespace.name)))
        elif command == "list":
            records = list_command.list_worktrees(cast(list[str], namespace.names))
            for record in records:
                path = "-" if record.path is None else os.fspath(record.path)
                print(f"{record.name}\t{path}\t{record.status}")
            if any(record.status != "ok" for record in records):
                return 1
        elif command == "remove":
            remove.remove_worktree(cast(str, namespace.name), confirm=cast(bool, namespace.yes))
        else:
            raise AssertionError(f"unhandled command: {command}")
    except WorktreeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0
