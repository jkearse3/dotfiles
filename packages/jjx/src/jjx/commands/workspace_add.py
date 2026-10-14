"""Create a jj workspace and prepare it the way a new Git worktree is prepared.

``jj workspace add`` creates its Git worktree without running Git's
``post-checkout`` hook, so the per-worktree preparation that hook performs
never happens. This command runs ``jj workspace add`` with the caller's
arguments, then runs the same preparation steps in the new workspace.
"""

from __future__ import annotations

import os
import shlex
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path

from .process import capture_bytes, checked_bytes


FOLLOW_UPS: tuple[tuple[str, ...], ...] = (
    ("worktree-include", "--prepare"),
    ("direnv-worktree", "prepare"),
)
"""Commands run in order in every new workspace, each given its root as the last argument."""

REPOSITORY_OPTIONS = ("-R", "--repository")

USAGE = """\
usage: {prog} [jj workspace add arguments]

Run 'jj workspace add' with the given arguments, then prepare the new workspace
as Git's post-checkout hook prepares a new worktree:

  1. worktree-include --prepare copies the local files the primary
     checkout's .worktreeinclude selects.
  2. direnv-worktree prepare authorizes the workspace's .envrc when the
     repository has enabled it.

Each step runs even if an earlier one fails. On success the workspace root is
printed on stdout and all other output goes to stderr. A workspace without its
own Git worktree, such as one created with --no-colocate, is not prepared.

Run from inside the repository; -R/--repository is not supported. See
'jj workspace add --help' for the accepted arguments.
"""


class WorkspaceAddError(Exception):
    """A concise, user-facing creation or preparation failure."""


def add(arguments: Sequence[str]) -> Path:
    """Create a workspace from ARGUMENTS and prepare it, returning its root.

    Raises WorkspaceAddError when the workspace cannot be created or
    identified, or after running every preparation step when any of them
    failed. A created workspace is never removed.
    """
    _reject_repository_option(arguments)

    existing = _workspace_names()
    status = _run_to_stderr(["jj", "workspace", "add", *arguments])
    if status != 0:
        raise WorkspaceAddError(f"jj workspace add failed with exit status {status}")

    root = _workspace_root(_new_workspace_name(existing))
    if not _is_git_worktree(root):
        print(
            f"warning: {root} has no Git worktree of its own; skipped preparation",
            file=sys.stderr,
        )
        return root

    failed = [
        command
        for command in (follow_up + (os.fspath(root),) for follow_up in FOLLOW_UPS)
        if _run_to_stderr(command) != 0
    ]
    if len(failed) != 0:
        recovery = "; ".join(shlex.join(command) for command in failed)
        raise WorkspaceAddError(
            f"created workspace at {root}, but preparation failed; "
            f"after fixing the cause, rerun: {recovery}"
        )
    return root


def _reject_repository_option(arguments: Sequence[str]) -> None:
    if any(argument.startswith(REPOSITORY_OPTIONS) for argument in _options(arguments)):
        raise WorkspaceAddError(
            "-R/--repository is not supported; run from inside the repository"
        )


def _options(arguments: Sequence[str]) -> list[str]:
    """Return ARGUMENTS before any ``--``, after which nothing is an option."""
    arguments = list(arguments)
    return arguments[: arguments.index("--")] if "--" in arguments else arguments


def _workspace_names() -> set[str]:
    output = _jj("workspace", "list", "-T", 'name ++ "\\n"')
    return set(os.fsdecode(output).splitlines())


def _new_workspace_name(existing: set[str]) -> str:
    added = _workspace_names() - existing
    if len(added) != 1:
        raise WorkspaceAddError(
            "jj workspace add succeeded, but the new workspace could not be identified; "
            "prepare it manually"
        )
    return added.pop()


def _workspace_root(name: str) -> Path:
    output = _jj("workspace", "root", "--name", name)
    return Path(os.fsdecode(output.removesuffix(b"\n")))


def _is_git_worktree(root: Path) -> bool:
    """Return whether ROOT is the top level of its own Git worktree."""
    result = capture_bytes(
        ["git", "-C", os.fspath(root), "rev-parse", "--show-toplevel"],
        error_type=WorkspaceAddError,
    )
    if result.returncode != 0:
        return False
    top_level = Path(os.fsdecode(result.stdout.removesuffix(b"\n")))
    return os.path.samefile(top_level, root)


def _jj(*arguments: str) -> bytes:
    return checked_bytes(
        ["jj", "--no-pager", "--color=never", "--ignore-working-copy", *arguments],
        error_type=WorkspaceAddError,
    )


def _run_to_stderr(command: Sequence[str]) -> int:
    """Run COMMAND with its stdout sent to stderr, keeping stdout for the root."""
    _ = sys.stdout.flush()
    try:
        return subprocess.run(command, check=False, stdout=sys.stderr).returncode
    except OSError as error:
        print(f"error: could not run {command[0]}: {error}", file=sys.stderr)
        return 127


def main(
    arguments: Sequence[str] | None = None,
    *,
    prog: str = "jjx workspace add",
) -> int:
    """Run the CLI and print the new workspace root."""
    argv = list(sys.argv[1:] if arguments is None else arguments)
    if any(argument in ("-h", "--help") for argument in _options(argv)):
        print(USAGE.format(prog=prog), end="")
        return 0
    try:
        print(add(argv))
    except WorkspaceAddError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0
