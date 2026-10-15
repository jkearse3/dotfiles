"""Remove a jj workspace created by ``jj workspace add``.

The checkout must be a shared workspace as ``jjx ensure`` defines it, so a
repository's own workspace and a Git worktree with independent jj state are
refused rather than deleted. Removal runs ``jj workspace remove``, which
snapshots the working copy into a commit and then deletes the workspace's Git
worktree and directory.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import cast

from . import ensure as ensure_command
from .process import checked_bytes


class WorkspaceRemoveError(Exception):
    """A concise, user-facing removal failure."""


@dataclass(frozen=True)
class SharedWorkspace:
    """A removable jj workspace: its name in the repository and its root."""

    name: str
    root: Path


def find(start: Path) -> SharedWorkspace:
    """Return the shared jj workspace containing START.

    Raises WorkspaceRemoveError when START is not inside a shared workspace
    that ``jjx ensure`` accepts, or when jj lists no workspace rooted there.
    """
    try:
        inspection = ensure_command.inspect(start)
    except ensure_command.EnsureError as error:
        raise WorkspaceRemoveError(str(error)) from error
    root = inspection.checkout.root
    if inspection.action is not ensure_command.Action.SHARED_WORKSPACE:
        raise WorkspaceRemoveError(
            f"{root} is not a workspace created by jj workspace add"
        )

    output = checked_bytes(
        [
            "jj",
            "--no-pager",
            "--color=never",
            "--ignore-working-copy",
            "-R",
            os.fspath(root),
            "workspace",
            "list",
            "-T",
            'name ++ "\\0" ++ if(root, root) ++ "\\0"',
        ],
        error_type=WorkspaceRemoveError,
    )
    fields = output.split(b"\0")
    for name, workspace_root in zip(fields[0:-1:2], fields[1::2]):
        if workspace_root != b"" and _is_same_path(Path(os.fsdecode(workspace_root)), root):
            return SharedWorkspace(os.fsdecode(name), root)
    raise WorkspaceRemoveError(f"jj lists no workspace rooted at {root}")


def remove(workspace: SharedWorkspace) -> None:
    """Remove WORKSPACE with ``jj workspace remove``, deleting its directory.

    jj runs from outside the workspace, through the workspace's own path, so
    the workspace's repository is used even when another linked worktree owns
    it. Raises WorkspaceRemoveError when jj fails.
    """
    _ = sys.stdout.flush()
    status = subprocess.run(
        ["jj", "-R", os.fspath(workspace.root), "workspace", "remove", workspace.name],
        cwd="/",
        check=False,
        stdout=sys.stderr,
    ).returncode
    if status != 0:
        raise WorkspaceRemoveError(f"jj workspace remove failed with exit status {status}")


def _is_same_path(first: Path, second: Path) -> bool:
    try:
        return os.path.samefile(first, second)
    except OSError:
        return False


def create_parser(prog: str = "jjx workspace remove") -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=prog,
        description=(
            "Remove the jj workspace containing PATH, which jj workspace add must "
            "have created. Its working copy is snapshotted into a commit first; "
            "ignored files are deleted with the directory."
        ),
    )
    _ = parser.add_argument(
        "path",
        metavar="PATH",
        nargs="?",
        default=".",
        help="a path inside the workspace (default: the current directory)",
    )
    _ = parser.add_argument(
        "--dry-run",
        action="store_true",
        help="validate the workspace and report what would be removed",
    )
    return parser


def main(
    arguments: Sequence[str] | None = None,
    *,
    prog: str = "jjx workspace remove",
) -> int:
    """Run the CLI, printing the workspace that is or would be removed."""
    namespace = create_parser(prog).parse_args(arguments)
    try:
        workspace = find(Path(cast(str, namespace.path)))
        if cast(bool, namespace.dry_run):
            print(f"would remove jj workspace {workspace.name} at {workspace.root}")
        else:
            remove(workspace)
            print(f"removed jj workspace {workspace.name} at {workspace.root}")
    except (OSError, WorkspaceRemoveError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0
