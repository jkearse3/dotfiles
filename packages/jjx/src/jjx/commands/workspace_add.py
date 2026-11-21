"""Create a jj workspace and prepare it the way a new Git worktree is prepared.

``jj workspace add`` creates its Git worktree without running Git's
``post-checkout`` hook, so the per-worktree preparation that hook performs
never happens. This command runs ``jj workspace add`` with the caller's
arguments plus ``--colocate``, then runs the same preparation steps in the new
workspace. Only colocated workspaces are supported: ``--no-colocate`` is
rejected, and a new workspace without its own Git worktree is an error.

When the arguments give ``--name`` but no destination, the workspace is created
at ``~/.worktrees/<repository>/<name>``; see ``default_destination``.
"""

from __future__ import annotations

import os
import shlex
import subprocess
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from .process import capture_bytes, checked_bytes


FOLLOW_UPS: tuple[tuple[str, ...], ...] = (
    ("worktree-include", "--prepare"),
    ("direnv-worktree", "prepare"),
)
"""Commands run in order in every new workspace, each given its root as the last argument."""

REPOSITORY_OPTIONS = ("-R", "--repository")

NO_COLOCATE_OPTION = "--no-colocate"

NAME_OPTION = "--name"

LONG_OPTIONS_WITH_VALUES = frozenset(
    {
        NAME_OPTION,
        "--revision",
        "--message",
        "--sparse-patterns",
        "--repository",
        "--at-operation",
        "--at-op",
        "--color",
        "--config",
        "--config-file",
    }
)
"""Long options of ``jj workspace add``, global ones included, that take a value."""

SHORT_OPTIONS_WITH_VALUES = frozenset("rmR")
"""Short options of ``jj workspace add``, global ones included, that take a value."""

WORKTREES_DIRECTORY = ".worktrees"
"""Folder under the home directory that holds default workspace destinations."""

OUTSIDE_HOME_DIRECTORY = "_"
"""Folder under WORKTREES_DIRECTORY for repositories outside the home directory."""

USAGE = """\
usage: {prog} [jj workspace add options] [DESTINATION]

Run 'jj workspace add --colocate' with the given arguments, then prepare the
new workspace as Git's post-checkout hook prepares a new worktree:

  1. worktree-include --prepare copies the local files the primary
     checkout's .worktreeinclude selects.
  2. direnv-worktree prepare authorizes the workspace's .envrc when the
     repository has enabled it.

Each step runs even if an earlier one fails. On success the workspace root is
printed on stdout and all other output goes to stderr.

Only colocated workspaces are supported: --no-colocate is rejected, and if the
new workspace has no Git worktree of its own, the command fails without
preparing it and names the 'jj workspace remove' command that removes it.

When --name NAME is given without a DESTINATION, the workspace is created at
~/.worktrees/<repository>/NAME, creating missing parent folders. <repository>
is the primary checkout's path relative to the home directory, such as
'dotfiles' for ~/dotfiles, or '_/' followed by its absolute path without the
leading '/' when it lies outside the home directory, such as _/srv/app. The
primary checkout is the same from any of its workspaces. With neither --name
nor DESTINATION, jj reports the missing destination.

Run from inside the repository; -R/--repository is not supported. See
'jj workspace add --help' for the accepted arguments.
"""


class WorkspaceAddError(Exception):
    """A concise, user-facing creation or preparation failure."""


def add(arguments: Sequence[str]) -> Path:
    """Create a colocated workspace from ARGUMENTS and prepare it, returning its root.

    ``--colocate`` is always passed to ``jj workspace add``. Raises
    WorkspaceAddError when ARGUMENTS contain ``--no-colocate`` or
    -R/--repository, when the workspace cannot be created or identified, when
    the created workspace has no Git worktree of its own (before any
    preparation), or after running every preparation step when any of them
    failed. A created workspace is never removed.

    When ARGUMENTS give ``--name`` but no destination, the destination is
    ``default_destination``'s, and its missing parent folders are created
    before ``jj workspace add`` runs.
    """
    _reject_repository_option(arguments)
    _reject_no_colocate(arguments)

    destination_arguments = _parse_destination_arguments(arguments)
    if not destination_arguments.has_destination and destination_arguments.name is not None:
        destination = default_destination(destination_arguments.name)
        try:
            destination.parent.mkdir(parents=True, exist_ok=True)
        except OSError as error:
            raise WorkspaceAddError(f"could not create {destination.parent}: {error}") from error
        arguments = [*arguments, os.fspath(destination)]

    existing = _workspace_names()
    status = _run_to_stderr(["jj", "workspace", "add", "--colocate", *arguments])
    if status != 0:
        raise WorkspaceAddError(f"jj workspace add failed with exit status {status}")

    name = _new_workspace_name(existing)
    root = _workspace_root(name)
    if not _is_git_worktree(root):
        removal = shlex.join(["jj", "workspace", "remove", name])
        raise WorkspaceAddError(
            f"created workspace {name} at {root}, but it has no Git worktree of its own; "
            f"jjx supports only colocated workspaces; remove it with: {removal}"
        )

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


@dataclass(frozen=True)
class _DestinationArguments:
    """What ``jj workspace add`` arguments say about where the workspace goes.

    ``name`` is the last ``--name`` value, or None when none is given;
    ``has_destination`` is whether any positional argument is given.
    """

    name: str | None
    has_destination: bool


def _parse_destination_arguments(arguments: Sequence[str]) -> _DestinationArguments:
    """Parse ARGUMENTS as clap parses ``jj workspace add``'s command line.

    Long options take their value after ``=`` or as the next argument; short
    options may be bundled, and a value-taking one takes the rest of the
    argument or the next one. A next argument that looks like an option is not
    taken as a value, so the option has none, as in jj. A lone ``-`` and
    everything after ``--`` are positional. Malformed arguments are left for jj
    to report.
    """
    name: str | None = None
    has_destination = False
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        index += 1
        if argument == "--":
            has_destination = has_destination or index < len(arguments)
            break

        if argument.startswith("--"):
            option, separator, value = argument.partition("=")
            if separator == "" and option in LONG_OPTIONS_WITH_VALUES:
                value = _next_value(arguments, index)
                if value is not None:
                    index += 1
            if option == NAME_OPTION and value is not None:
                name = value
        elif _is_option(argument):
            for position, letter in enumerate(argument[1:], start=1):
                if letter in SHORT_OPTIONS_WITH_VALUES:
                    if position == len(argument) - 1 and _next_value(arguments, index) is not None:
                        index += 1
                    break
        else:
            has_destination = True
    return _DestinationArguments(
        name=name,
        has_destination=has_destination,
    )


def _next_value(arguments: Sequence[str], index: int) -> str | None:
    """Return the option value at INDEX, or None when there is none to take."""
    if index < len(arguments) and not _is_option(arguments[index]):
        return arguments[index]
    return None


def _is_option(argument: str) -> bool:
    return argument.startswith("-") and argument != "-"


def default_destination(name: str) -> Path:
    """Return where a workspace named NAME goes when no destination is given.

    The path is ``~/.worktrees/<repository>/<NAME>``, where ``<repository>``
    is the primary checkout's path relative to the home directory, or ``_/``
    followed by its absolute path without the leading ``/`` when it lies
    outside the home directory. Both paths are compared with symlinks
    resolved; the result keeps the home directory as ``$HOME`` spells it.
    Raises WorkspaceAddError when NAME is not a single path component, or when
    the current directory is not inside a jj workspace.
    """
    if name in ("", ".", "..") or "/" in name:
        raise WorkspaceAddError(
            f"workspace name {name!r} cannot name a folder under ~/{WORKTREES_DIRECTORY}; "
            "give a destination"
        )

    home = Path.home()
    primary = _primary_checkout()
    try:
        repository = primary.relative_to(home.resolve())
    except ValueError:
        repository = Path(OUTSIDE_HOME_DIRECTORY, *primary.parts[1:])
    return home / WORKTREES_DIRECTORY / repository / name


def _primary_checkout() -> Path:
    """Return the resolved root of the workspace that owns the current workspace's repository.

    A workspace added by ``jj workspace add`` has a ``.jj/repo`` file holding
    the path, relative to its ``.jj`` folder, of the owning workspace's
    ``.jj/repo`` directory; the owning workspace has that directory itself.
    """
    workspace = Path(os.fsdecode(_jj("workspace", "root").removesuffix(b"\n")))
    repository = workspace / ".jj" / "repo"
    if repository.is_file():
        try:
            pointer = repository.read_bytes().removesuffix(b"\n")
        except OSError as error:
            raise WorkspaceAddError(f"could not read {repository}: {error}") from error
        repository = workspace / ".jj" / os.fsdecode(pointer)
    return repository.resolve().parent.parent


def _reject_repository_option(arguments: Sequence[str]) -> None:
    if any(argument.startswith(REPOSITORY_OPTIONS) for argument in _options(arguments)):
        raise WorkspaceAddError(
            "-R/--repository is not supported; run from inside the repository"
        )


def _reject_no_colocate(arguments: Sequence[str]) -> None:
    if any(
        argument == NO_COLOCATE_OPTION or argument.startswith(f"{NO_COLOCATE_OPTION}=")
        for argument in _options(arguments)
    ):
        raise WorkspaceAddError(
            "--no-colocate is not supported; "
            "jjx workspace add creates only colocated workspaces"
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
