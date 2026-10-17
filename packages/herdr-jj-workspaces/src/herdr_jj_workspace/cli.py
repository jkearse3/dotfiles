"""Create and remove jj workspaces as Herdr worktree workspaces.

Herdr's own worktree commands manage only Git worktrees. ``add`` creates a jj
workspace with ``jjx workspace add`` in Herdr's worktree directory and opens it
in Herdr, grouped under the repository's primary checkout even when started
from another of its workspaces; ``remove`` removes one with
``jjx workspace remove`` and closes its Herdr workspace. Both target
the calling pane's Herdr workspace unless ``--workspace`` names another, and
neither moves the user's focus unless ``--focus`` is given.

The ``prompt-add`` and ``prompt-remove`` commands are the dotfiles.jj-workspaces
plugin's popups, and ``open-popup`` is its action command.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import cast

# Herdr's default worktree directory, which also holds its own worktrees.
WORKTREES_DIRECTORY = Path.home() / ".herdr" / "worktrees"

PROGRAM = "herdr-jj-workspace"


class WorkspaceError(Exception):
    """A concise, user-facing failure."""


@dataclass(frozen=True)
class Source:
    """The repository of the Herdr workspace a new jj workspace is created from.

    PARENT_WORKSPACE_ID is the Herdr workspace showing the repository's primary
    checkout, which Herdr requires new worktree workspaces to be opened from.
    """

    parent_workspace_id: str
    repo_root: Path
    repo_name: str


@dataclass(frozen=True)
class Target:
    """A Herdr workspace showing a checkout that may be a removable jj workspace."""

    workspace_id: str
    checkout: Path
    repo_root: str


def resolve_source(workspace_id: str) -> Source:
    """Return the repository Herdr places WORKSPACE_ID in.

    Herdr resolves it from the workspace's checkout or pane directory, including
    workspaces it has not yet marked as Git workspaces, and resolves a linked
    worktree such as another jj workspace to its primary checkout.
    """
    try:
        response = _herdr_json("worktree", "list", "--workspace", workspace_id)
    except WorkspaceError as error:
        raise WorkspaceError(
            f"Herdr workspace {workspace_id} is not in a Git repository"
        ) from error
    source = _object(_object(response.get("result")).get("source"))
    repo_root = _string(source.get("repo_root"))
    repo_name = _string(source.get("repo_name"))
    # Herdr names the parent even for a linked worktree, and refuses to close
    # the parent while linked ones are open; the fallback covers older reports.
    parent_workspace_id = _string(source.get("source_workspace_id"))
    if parent_workspace_id == "":
        parent_workspace_id = workspace_id
    if repo_root == "" or repo_name == "":
        raise WorkspaceError(f"Herdr reported no repository for workspace {workspace_id}")
    if not (Path(repo_root) / ".jj").is_dir():
        raise WorkspaceError(f"{repo_root} has no jj repository; run jjx ensure there first")
    return Source(parent_workspace_id, Path(repo_root), repo_name)


def validate_name(name: str) -> None:
    """Require NAME to be one path component usable as a jj workspace name."""
    if name in ("", ".", "..") or name.startswith("-") or "/" in name:
        raise WorkspaceError("the name must be one path component that does not start with -")


def create(source: Source, name: str, *, focus: bool) -> dict[str, str]:
    """Create jj workspace NAME from SOURCE and open it in Herdr.

    Returns the new checkout's path and the Herdr workspace and root pane that
    show it.
    """
    validate_name(name)
    destination = WORKTREES_DIRECTORY / source.repo_name / name
    if destination.exists() or destination.is_symlink():
        raise WorkspaceError(f"{destination} already exists")
    destination.parent.mkdir(parents=True, exist_ok=True)

    # Start from trunk rather than the primary checkout's @, so a new workspace
    # never builds on another workspace's unfinished work. jjx reports progress
    # on stderr and prints only the new root on stdout.
    command = ["jjx", "workspace", "add", "--name", name, "--revision", "trunk()", "--", str(destination)]
    result = _run(command, cwd=source.repo_root, stderr=None)
    if result.returncode != 0:
        raise WorkspaceError("jjx workspace add failed; see its output above")
    root = result.stdout.removesuffix("\n")

    # Opening from the parent workspace groups the new one under it, as Herdr's
    # own new_worktree does; Herdr refuses to open from a linked worktree.
    try:
        response = _herdr_json(
            "worktree",
            "open",
            "--workspace",
            source.parent_workspace_id,
            "--path",
            root,
            "--focus" if focus else "--no-focus",
        )
    except WorkspaceError as error:
        raise WorkspaceError(f"created {root}, but Herdr could not open it: {error}") from error
    opened = _object(response.get("result"))
    return {
        "path": root,
        "workspace_id": _string(_object(opened.get("workspace")).get("workspace_id")),
        "pane_id": _string(_object(opened.get("root_pane")).get("pane_id")),
    }


def resolve_target(workspace_id: str) -> Target:
    """Return the checkout Herdr workspace WORKSPACE_ID shows."""
    for workspace in _workspaces():
        if workspace.get("workspace_id") != workspace_id:
            continue
        worktree = _object(workspace.get("worktree"))
        checkout = _string(worktree.get("checkout_path"))
        if checkout == "":
            break
        return Target(workspace_id, Path(checkout), _string(worktree.get("repo_root")))
    raise WorkspaceError(f"Herdr workspace {workspace_id} is not a Git worktree")


def describe_removal(target: Target) -> str:
    """Return jjx's description of removing TARGET, or fail if it is not removable.

    jjx refuses anything jj workspace add did not create, such as Git
    worktrees, which Herdr's remove_worktree handles instead, and primary
    checkouts.
    """
    result = _run(["jjx", "workspace", "remove", "--dry-run", str(target.checkout)], stderr=None)
    if result.returncode != 0:
        raise WorkspaceError(f"{target.checkout} is not a removable jj workspace; see the output above")
    return result.stdout.removesuffix("\n")


def remove(target: Target, *, focus: bool) -> str:
    """Remove TARGET's jj workspace and close its Herdr workspace.

    With FOCUS, focuses the Herdr workspace showing the repository's primary
    checkout afterwards. Returns jjx's report.
    """
    primary_workspace_id = _primary_workspace_id(target.repo_root) if focus else None
    result = _run(["jjx", "workspace", "remove", str(target.checkout)], stderr=None)
    if result.returncode != 0:
        raise WorkspaceError("jjx workspace remove failed; see its output above")
    report = result.stdout.removesuffix("\n")
    try:
        _ = _herdr_json("workspace", "close", target.workspace_id)
    except WorkspaceError as error:
        raise WorkspaceError(
            f"removed the jj workspace, but Herdr could not close workspace {target.workspace_id}: {error}"
        ) from error
    # Focusing is a convenience; Herdr already moved focus somewhere usable.
    if primary_workspace_id is not None:
        try:
            _ = _herdr_json("workspace", "focus", primary_workspace_id)
        except WorkspaceError:
            pass
    return report


def _primary_workspace_id(repo_root: str) -> str | None:
    for workspace in _workspaces():
        worktree = _object(workspace.get("worktree"))
        if worktree.get("repo_root") == repo_root and worktree.get("is_linked_worktree") is False:
            workspace_id = _string(workspace.get("workspace_id"))
            if workspace_id != "":
                return workspace_id
    return None


def _workspaces() -> list[dict[str, object]]:
    workspaces = _object(_herdr_json("workspace", "list").get("result")).get("workspaces")
    if not isinstance(workspaces, list):
        raise WorkspaceError("Herdr returned no workspace list")
    return [_object(workspace) for workspace in cast(list[object], workspaces)]


def _herdr_json(*arguments: str) -> dict[str, object]:
    command = [_herdr(), *arguments]
    result = _run(command)
    if result.returncode != 0:
        detail = result.stderr.strip()
        raise WorkspaceError(f"{shlex.join(command)} failed" + (f": {detail}" if detail != "" else ""))
    try:
        return _object(cast(object, json.loads(result.stdout)))
    except json.JSONDecodeError as error:
        raise WorkspaceError(f"{shlex.join(command)} returned malformed JSON") from error


def _herdr() -> str:
    herdr = os.environ.get("HERDR_BIN_PATH", "")
    return herdr if herdr != "" else "herdr"


def _run(
    command: Sequence[str],
    *,
    cwd: Path | None = None,
    stderr: int | None = subprocess.PIPE,
) -> subprocess.CompletedProcess[str]:
    """Run COMMAND capturing stdout, and stderr unless STDERR is None."""
    _ = sys.stdout.flush()
    try:
        return subprocess.run(
            command, cwd=cwd, check=False, stdout=subprocess.PIPE, stderr=stderr, text=True
        )
    except OSError as error:
        raise WorkspaceError(f"could not run {command[0]}: {error}") from error


def _object(value: object) -> dict[str, object]:
    return cast(dict[str, object], value) if isinstance(value, dict) else {}


def _string(value: object) -> str:
    return value if isinstance(value, str) else ""


def _caller_workspace(workspace_id: str | None) -> str:
    resolved = workspace_id if workspace_id is not None else os.environ.get("HERDR_WORKSPACE_ID", "")
    if resolved == "":
        raise WorkspaceError("not running in a Herdr pane; pass --workspace")
    return resolved


def _plugin_workspace() -> str:
    context = os.environ.get("HERDR_PLUGIN_CONTEXT_JSON", "")
    try:
        workspace_id = _string(_object(cast(object, json.loads(context))).get("workspace_id"))
    except json.JSONDecodeError:
        workspace_id = ""
    if workspace_id == "":
        raise WorkspaceError("Herdr reported no current workspace")
    return workspace_id


def _command_add(arguments: argparse.Namespace) -> int:
    name = cast(str, arguments.name)
    validate_name(name)
    source = resolve_source(_caller_workspace(cast(str | None, arguments.workspace)))
    print(json.dumps(create(source, name, focus=cast(bool, arguments.focus))))
    return 0


def _command_remove(arguments: argparse.Namespace) -> int:
    target = resolve_target(_caller_workspace(cast(str | None, arguments.workspace)))
    summary = describe_removal(target)
    if cast(bool, arguments.dry_run):
        print(summary)
        return 0
    print(remove(target, focus=cast(bool, arguments.focus)))
    return 0


def _command_prompt_add(_arguments: argparse.Namespace) -> int:
    source = resolve_source(_plugin_workspace())
    print(f"New jj workspace for {source.repo_name}\n")
    name = input("Name: ")
    _ = create(source, name, focus=True)
    return 0


def _command_prompt_remove(_arguments: argparse.Namespace) -> int:
    target = resolve_target(_plugin_workspace())
    print(describe_removal(target) + "\n")
    print("This deletes the directory and closes its Herdr workspace.")
    print("jj snapshots its working copy into a commit first; ignored files are lost.\n")
    if input("Remove? [y/N] ") in ("y", "Y"):
        _ = remove(target, focus=True)
    return 0


def _command_open_popup(arguments: argparse.Namespace) -> int:
    # Keys can bind only plugin actions, and an action runs without a terminal,
    # so each action opens its popup.
    plugin_id = os.environ.get("HERDR_PLUGIN_ID", "")
    if plugin_id == "":
        raise WorkspaceError("HERDR_PLUGIN_ID is not set; run this as a Herdr plugin action")
    command = [_herdr(), "plugin", "pane", "open", "--plugin", plugin_id]
    command += ["--entrypoint", cast(str, arguments.entrypoint), "--focus"]
    return _run(command, stderr=None).returncode


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=PROGRAM,
        description="Create and remove jj workspaces as Herdr worktree workspaces.",
    )
    commands = parser.add_subparsers(dest="command", required=True, metavar="COMMAND")

    add = commands.add_parser(
        "add",
        help="create a jj workspace from trunk and open it in Herdr",
        description=(
            "Create jj workspace NAME from trunk() in ~/.herdr/worktrees/REPO/NAME "
            "for the repository of a Herdr workspace, which may show any of its "
            "checkouts, and open it in Herdr grouped under the primary checkout's "
            "workspace. Prints the new checkout's path and the Herdr "
            "workspace_id and pane_id showing it as JSON."
        ),
    )
    _ = add.add_argument("name", metavar="NAME", help="workspace and directory name")
    _add_common_options(add, "workspace whose repository to use")
    add.set_defaults(handler=_command_add)

    remove_parser = commands.add_parser(
        "remove",
        help="remove a Herdr workspace's jj workspace and close it",
        description=(
            "Remove the jj workspace a Herdr workspace shows with jjx workspace "
            "remove, which snapshots its working copy into a commit and deletes "
            "the directory, then close the Herdr workspace. Primary checkouts and "
            "Git worktrees are refused."
        ),
    )
    _add_common_options(remove_parser, "workspace to remove")
    _ = remove_parser.add_argument(
        "--dry-run", action="store_true", help="report what would be removed and change nothing"
    )
    remove_parser.set_defaults(handler=_command_remove)

    for name, handler in (("prompt-add", _command_prompt_add), ("prompt-remove", _command_prompt_remove)):
        prompt = commands.add_parser(name, help=f"plugin popup for {name.removeprefix('prompt-')}")
        prompt.set_defaults(handler=handler, popup=True)

    popup = commands.add_parser("open-popup", help="plugin action that opens a popup pane")
    _ = popup.add_argument("entrypoint", metavar="ENTRYPOINT")
    popup.set_defaults(handler=_command_open_popup)
    return parser


def _add_common_options(parser: argparse.ArgumentParser, workspace_help: str) -> None:
    _ = parser.add_argument(
        "--workspace",
        metavar="ID",
        help=f"Herdr {workspace_help} (default: $HERDR_WORKSPACE_ID, the calling pane's)",
    )
    _ = parser.add_argument(
        "--focus", action="store_true", help="move the user's Herdr focus to the result"
    )


def main(arguments: Sequence[str] | None = None) -> int:
    """Run the CLI."""
    parsed = _parser().parse_args(arguments)
    handler = cast(Callable[[argparse.Namespace], int], parsed.handler)
    popup = cast(bool, getattr(parsed, "popup", False))
    try:
        return handler(parsed)
    except (EOFError, KeyboardInterrupt):
        return 1
    except WorkspaceError as error:
        print(f"error: {error}", file=sys.stderr)
        if not popup:
            return 1
    # A popup closes when its command exits, so keep the error readable.
    print("\nPress enter to close.", end="", file=sys.stderr)
    try:
        _ = input()
    except (EOFError, KeyboardInterrupt):
        pass
    return 1
