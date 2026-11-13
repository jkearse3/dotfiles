"""Create and remove jj workspaces as Herdr worktree workspaces.

Herdr's own worktree commands manage only Git worktrees. ``add`` creates a jj
workspace with ``jjx workspace add`` in Herdr's worktree directory, starting
from ``trunk()`` unless ``--revision`` names another revision, and opens it in
Herdr, grouped under the repository's primary checkout even when started
from another of its workspaces; ``remove`` removes one with
``jjx workspace remove`` and closes its Herdr workspace. Both target
the calling pane's Herdr workspace unless ``--workspace`` names another, and
neither moves the user's focus unless ``--focus`` is given.

The ``prompt-add`` and ``prompt-remove`` commands are the dotfiles.jj-workspaces
plugin's popups, and ``open-popup`` is its action command. ``prompt-add`` asks
for the name, then in fzf for the base revision: ``trunk()`` or one of the
repository's local bookmarks, for stacking on unfinished work.

``--host`` names which Herdr ``add``, ``remove``, ``prompt-add`` and
``prompt-remove`` drive: ``tui``, the Herdr terminal UI through its ``herdr``
CLI, or ``app``, the Herdr desktop app through ``herdr-app`` and herdr-core's
``hc``. Under ``app``, a workspace is an app space and ``--workspace`` takes a
space ID; a new jj workspace comes from the repository of the process's working
directory unless ``--workspace`` names a space, and opens as a new space.
``prompt-add --pick`` instead asks in fzf which repository of the app's spaces
on this machine to use, listing first the repository of the folder ``--first``
names.
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
from typing import Literal, cast

# Herdr's default worktree directory, which also holds its own worktrees.
WORKTREES_DIRECTORY = Path.home() / ".herdr" / "worktrees"

PROGRAM = "herdr-jj-workspace"

# The revision a new workspace starts from unless the caller names another.
# trunk() rather than the primary checkout's @, so a new workspace never builds
# on another workspace's unfinished work.
DEFAULT_REVISION = "trunk()"


class WorkspaceError(Exception):
    """A concise, user-facing failure."""


# Which Herdr a command drives: the terminal UI or the desktop app.
Host = Literal["tui", "app"]
HOSTS: tuple[Host, ...] = ("tui", "app")


def default_host() -> Host:
    """Return the Herdr this process runs in, for when --host is omitted.

    A terminal of the desktop app's core has $HC_TERMINAL_ID; the TUI sets
    HERDR_ENV=1 in its panes and plugin popups, including a TUI running inside
    an app terminal. Anything else, such as a plain shell, counts as the TUI.
    """
    in_core_terminal = os.environ.get("HC_TERMINAL_ID", "") != ""
    return "app" if in_core_terminal and os.environ.get("HERDR_ENV") != "1" else "tui"


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


def create(source: Source, name: str, *, revision: str, focus: bool) -> dict[str, str]:
    """Create jj workspace NAME of SOURCE's repository on REVISION and open it in Herdr.

    REVISION is a jj revset naming the commit the workspace's @ starts on top
    of. Returns the new checkout's path and the Herdr workspace and root pane that
    show it.
    """
    root = _add_jj_workspace(source.repo_root, source.repo_name, name, revision)

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


def _add_jj_workspace(repo_root: Path, repo_name: str, name: str, revision: str) -> str:
    """Create jj workspace NAME of the repository at REPO_ROOT on REVISION; return its root.

    The checkout goes to Herdr's worktree directory under REPO_NAME, and its @
    is a new commit on top of the revset REVISION. Raises WorkspaceError for an
    invalid name, an existing destination, or a jjx failure, such as a REVISION
    that does not resolve to one commit, whose output is left on stderr.
    """
    validate_name(name)
    destination = WORKTREES_DIRECTORY / repo_name / name
    if destination.exists() or destination.is_symlink():
        raise WorkspaceError(f"{destination} already exists")
    destination.parent.mkdir(parents=True, exist_ok=True)

    # The = form keeps a REVISION that starts with - from parsing as an option.
    # jjx reports progress on stderr and prints only the new root on stdout.
    command = ["jjx", "workspace", "add", "--name", name, f"--revision={revision}", "--", str(destination)]
    result = _run(command, cwd=repo_root, stderr=None)
    if result.returncode != 0:
        raise WorkspaceError("jjx workspace add failed; see its output above")
    return result.stdout.removesuffix("\n")


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


def describe_removal(checkout: Path) -> str:
    """Return jjx's description of removing the jj workspace at CHECKOUT, or fail if it is not removable.

    jjx refuses anything jj workspace add did not create, such as Git
    worktrees, which Herdr's remove_worktree handles instead, and primary
    checkouts.
    """
    result = _run(["jjx", "workspace", "remove", "--dry-run", str(checkout)], stderr=None)
    if result.returncode != 0:
        raise WorkspaceError(f"{checkout} is not a removable jj workspace; see the output above")
    return result.stdout.removesuffix("\n")


def remove(target: Target, *, focus: bool) -> str:
    """Remove TARGET's jj workspace and close its Herdr workspace.

    With FOCUS, focuses the Herdr workspace showing the repository's primary
    checkout afterwards. Returns jjx's report.
    """
    primary_workspace_id = _primary_workspace_id(target.repo_root) if focus else None
    report = _remove_jj_workspace(target.checkout)
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


def _remove_jj_workspace(checkout: Path) -> str:
    """Remove the jj workspace at CHECKOUT with jjx; return jjx's report.

    jjx snapshots the working copy into a commit before deleting the directory.
    """
    result = _run(["jjx", "workspace", "remove", str(checkout)], stderr=None)
    if result.returncode != 0:
        raise WorkspaceError("jjx workspace remove failed; see its output above")
    return result.stdout.removesuffix("\n")


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
    stdin_text: str | None = None,
    stderr: int | None = subprocess.PIPE,
) -> subprocess.CompletedProcess[str]:
    """Run COMMAND capturing stdout, and stderr unless STDERR is None.

    STDIN_TEXT, when given, is written to its stdin; otherwise it inherits this
    process's.
    """
    _ = sys.stdout.flush()
    try:
        return subprocess.run(
            command, cwd=cwd, input=stdin_text, check=False, stdout=subprocess.PIPE, stderr=stderr, text=True
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


# The desktop app host. The app window owns spaces, tabs and panes
# (``herdr-app ls``); its core owns terminals and where they are now (``hc``).
# Spaces on other machines are left out: this CLI acts on this machine only.


@dataclass(frozen=True)
class JjCheckout:
    """A jj workspace's root directory and its repository's primary checkout.

    The two are the same directory for the primary checkout itself.
    """

    root: Path
    primary_root: Path


def find_jj_checkout(folder: Path) -> JjCheckout | None:
    """Return the jj workspace FOLDER is in, or None outside one.

    A secondary workspace's ``.jj/repo`` is a file holding the primary
    checkout's ``.jj/repo`` directory, relative to the file's ``.jj``
    directory; the primary checkout's is that directory itself.
    """
    for root in (folder, *folder.parents):
        jj_directory = root / ".jj"
        if not jj_directory.is_dir():
            continue
        repo = jj_directory / "repo"
        if not repo.is_file():
            return JjCheckout(root=root, primary_root=root)
        try:
            shared_repo = (jj_directory / repo.read_text().strip()).resolve()
        except OSError as error:
            raise WorkspaceError(f"could not read {repo}: {error}") from error
        return JjCheckout(root=root, primary_root=shared_repo.parent.parent)
    return None


def resolve_app_source(folder: Path) -> JjCheckout:
    """Return the jj workspace FOLDER is in, which a new jj workspace is made from.

    Raises WorkspaceError outside a jj workspace.
    """
    checkout = find_jj_checkout(folder)
    if checkout is None:
        raise WorkspaceError(f"{folder} is not in a jj repository; run jjx ensure in its repository first")
    return checkout


# fzf's exit statuses when the user closes it without choosing: no line matched
# the query, or the user pressed Esc or ctrl-c.
FZF_NO_MATCH = 1
FZF_INTERRUPTED = 130


def pick_app_source(first: Path | None = None) -> JjCheckout | None:
    """Ask in fzf which repository of the app's spaces on this machine a new jj workspace is made from.

    fzf lists the primary checkout of FIRST's jj repository first, so Enter
    with an empty query picks it, even when no space is in that repository;
    a FIRST in no jj repository, or None, adds nothing. Then it lists, in
    sidebar order, the primary checkout of each jj repository a space is now
    in (see ``_app_space_live_folder``). Each repository appears once, even
    when several spaces show its checkouts. Returns the chosen primary
    checkout, or None when the user closes fzf without choosing. Raises
    WorkspaceError, before running fzf, when no window is open, hc fails, or
    neither FIRST nor any space is in a jj repository, and when fzf fails.
    """
    repositories: dict[str, JjCheckout] = {}

    def add(checkout: JjCheckout | None) -> None:
        if checkout is None:
            return
        primary_root = checkout.primary_root.resolve()
        primary = JjCheckout(root=primary_root, primary_root=primary_root)
        _ = repositories.setdefault(_home_relative(primary_root), primary)

    if first is not None:
        add(find_jj_checkout(first.absolute()))
    for space in _app_spaces():
        folder = _app_space_live_folder(space)
        add(find_jj_checkout(Path(folder)) if folder != "" else None)
    if len(repositories) == 0:
        raise WorkspaceError("no space on this machine is in a jj repository; run jjx ensure in one first")

    command = [_fzf(), "--scheme=path", "--prompt=New jj workspace> "]
    result = _run(command, stdin_text="".join(f"{line}\n" for line in repositories), stderr=None)
    if result.returncode in (FZF_NO_MATCH, FZF_INTERRUPTED):
        return None
    if result.returncode != 0:
        raise WorkspaceError(f"fzf exited with status {result.returncode}")

    chosen = repositories.get(result.stdout.removesuffix("\n"))
    if chosen is None:
        raise WorkspaceError(f"fzf printed {result.stdout!r}, which is not a listed repository")
    return chosen


def pick_base(repo_root: Path) -> str | None:
    """Ask in fzf which revision a new jj workspace of the repository at REPO_ROOT starts on top of.

    fzf lists ``trunk()`` first, so Enter with an empty query keeps the
    default, then the repository's local bookmarks, most recently committed
    first, each with its change ID and first description line; deleted and
    conflicted bookmarks are left out. Returns the chosen revset, or None when
    the user closes fzf without choosing. Without eligible bookmarks there is
    nothing to choose, so it returns ``trunk()`` without running fzf. Raises
    WorkspaceError when jj or fzf fails.
    """
    bases = {DEFAULT_REVISION: DEFAULT_REVISION, **_bookmark_bases(repo_root)}
    if len(bases) == 1:
        return DEFAULT_REVISION

    command = [_fzf(), "--prompt=Base revision> "]
    result = _run(command, stdin_text="".join(f"{line}\n" for line in bases), stderr=None)
    if result.returncode in (FZF_NO_MATCH, FZF_INTERRUPTED):
        return None
    if result.returncode != 0:
        raise WorkspaceError(f"fzf exited with status {result.returncode}")

    chosen = bases.get(result.stdout.removesuffix("\n"))
    if chosen is None:
        raise WorkspaceError(f"fzf printed {result.stdout!r}, which is not a listed base revision")
    return chosen


# One line per present, unconflicted local bookmark: its name as a JSON string,
# its target's change ID and the first line of its description, tab-separated.
_BOOKMARK_BASE_TEMPLATE = (
    'if(!remote && present && !conflict, json(name) ++ "\\t" ++ normal_target.change_id().shortest(8)'
    ' ++ "\\t" ++ normal_target.description().first_line() ++ "\\n")'
)


def _bookmark_bases(repo_root: Path) -> dict[str, str]:
    """Return fzf lines for the local bookmarks of the repository at REPO_ROOT, each mapped to its revset.

    Lines align the bookmark names and keep jj's most recently committed first
    order; each revset names its bookmark exactly. Raises WorkspaceError when
    jj fails or prints a name that is not a JSON string.
    """
    command = [
        "jj",
        "bookmark",
        "list",
        "--ignore-working-copy",
        "--sort",
        "committer-date-",
        "--color=never",
        "-T",
        _BOOKMARK_BASE_TEMPLATE,
    ]
    result = _run(command, cwd=repo_root)
    if result.returncode != 0:
        detail = result.stderr.strip()
        raise WorkspaceError("jj bookmark list failed" + (f": {detail}" if detail != "" else ""))

    bookmarks: list[tuple[str, str, str, str]] = []
    for row in result.stdout.splitlines():
        encoded_name, change_id, description = row.split("\t", 2)
        try:
            name = cast(object, json.loads(encoded_name))
        except json.JSONDecodeError as error:
            raise WorkspaceError(f"jj bookmark list printed malformed name {encoded_name!r}") from error
        if not isinstance(name, str):
            raise WorkspaceError(f"jj bookmark list printed malformed name {encoded_name!r}")
        bookmarks.append((name, encoded_name, change_id, description))

    name_width = max((len(name) for name, _, _, _ in bookmarks), default=0)
    return {
        f"{name:<{name_width}}  {change_id}  {description}".rstrip(): f"bookmarks(exact:{encoded_name})"
        for name, encoded_name, change_id, description in bookmarks
    }


def _home_relative(path: Path) -> str:
    """Return PATH with the home directory written as ``~``."""
    try:
        relative = path.relative_to(Path.home())
    except ValueError:
        return str(path)
    return "~" if relative == Path() else f"~/{relative}"


def _fzf() -> str:
    fzf = os.environ.get("HERDR_JJ_WORKSPACE_FZF_PATH", "")
    return fzf if fzf != "" else "fzf"


def app_create(source: JjCheckout, name: str, *, revision: str, focus: bool) -> dict[str, str]:
    """Create jj workspace NAME of SOURCE's repository on REVISION and open it as a new app space.

    REVISION is a jj revset naming the commit the workspace's @ starts on top
    of. Returns the new checkout's path, the space showing it as ``workspace_id``
    and its first terminal's address as ``pane_id``. Without FOCUS the space
    shown before is shown again. Raises WorkspaceError, before creating
    anything, when no app window is open.
    """
    # The window is asked first, so a missing window fails before jjx runs.
    shown_space_id = next((space.space_id for space in _app_spaces() if space.is_shown), "")
    primary_root = source.primary_root
    root = _add_jj_workspace(primary_root, primary_root.name, name, revision)

    # An unnamed space is named after its folder, and the app nests it under
    # its repository's space by the checkout's Git common directory.
    try:
        opened = _app_json("herdr-app", "do", "space.new", json.dumps({"folder": root}))
    except WorkspaceError as error:
        raise WorkspaceError(f"created {root}, but the Herdr app could not open it: {error}") from error
    space_id = _string(opened.get("space"))

    # space.new shows the new space; showing the previous one again is a
    # convenience, so its failure is reported without failing the command.
    if not focus and shown_space_id not in ("", space_id):
        _select_app_space_or_warn(shown_space_id)
    return {
        "path": root,
        "workspace_id": space_id,
        "pane_id": _string(opened.get("terminal")),
    }


@dataclass(frozen=True)
class AppTarget:
    """An app space showing a checkout that may be a removable jj workspace.

    CHECKOUT is the jj workspace root of the space's first terminal's folder,
    or that folder itself outside jj, which jjx then refuses.
    """

    space_id: str
    checkout: Path
    primary_root: Path


def resolve_app_target(space_id: str) -> AppTarget:
    """Return the checkout app space SPACE_ID shows: where its first terminal is now."""
    folder = app_space_folder(space_id)
    checkout = find_jj_checkout(folder)
    if checkout is None:
        return AppTarget(space_id=space_id, checkout=folder, primary_root=folder)
    return AppTarget(space_id=space_id, checkout=checkout.root, primary_root=checkout.primary_root)


def app_remove(target: AppTarget, *, focus: bool) -> str:
    """Remove TARGET's jj workspace and close its app space.

    With FOCUS, then shows a space now in the repository's primary checkout,
    when there is one. Returns jjx's report.
    """
    primary_space_id = _app_primary_space_id(target.primary_root) if focus else ""
    report = _remove_jj_workspace(target.checkout)
    try:
        _ = _app_json("herdr-app", "do", "space.close", json.dumps({"id": target.space_id, "confirmed": True}))
    except WorkspaceError as error:
        raise WorkspaceError(
            f"removed the jj workspace, but the Herdr app could not close space {target.space_id}: {error}"
        ) from error
    if primary_space_id != "":
        _select_app_space_or_warn(primary_space_id)
    return report


def app_caller_space() -> str:
    """Return the app space of the terminal $HC_TERMINAL_ID names, from its ``herdr.space`` label.

    The app sets that label on every terminal it shows in a pane. Raises
    WorkspaceError outside such a terminal.
    """
    address = os.environ.get("HC_TERMINAL_ID", "")
    if address != "":
        labels = _object(_app_json("hc", "get", address, "--json").get("labels"))
        space_id = _string(labels.get("herdr.space"))
        if space_id != "":
            return space_id
    raise WorkspaceError("not running in a Herdr app pane; pass --workspace")


def app_space_folder(space_id: str) -> Path:
    """Return where app space SPACE_ID's first terminal is now.

    The app takes a space's repository from there too. Raises WorkspaceError
    when the app has no such space or it shows no terminal.
    """
    space = next((space for space in _app_spaces() if space.space_id == space_id), None)
    if space is None:
        raise WorkspaceError(f"the Herdr app has no space {space_id}")
    if space.first_terminal == "":
        raise WorkspaceError(f"Herdr app space {space_id} shows no terminal")

    folder = _terminal_folder(space.first_terminal)
    if folder == "":
        raise WorkspaceError(f"hc reported no folder for terminal {space.first_terminal}")
    return Path(folder)


def _terminal_folder(address: str) -> str:
    """Return where terminal ADDRESS is now, from ``hc get``.

    Prefers its foreground process's folder over the terminal's own, and
    returns "" when hc reports neither. Raises WorkspaceError when hc fails.
    """
    record = _app_json("hc", "get", address, "--json")
    folder = _string(_object(record.get("foreground")).get("cwd"))
    if folder == "":
        folder = _string(record.get("cwd"))
    return folder


@dataclass(frozen=True)
class AppSpace:
    """A space of the app window on this machine, from ``herdr-app ls``.

    FOLDER is the folder it was made in, which stays put when its terminals
    ``cd`` elsewhere (``_app_space_live_folder`` returns where it is now);
    FIRST_TERMINAL is the address of its first tab's first terminal, or ""
    when it shows none.
    """

    space_id: str
    folder: str
    is_shown: bool
    first_terminal: str


def _app_spaces() -> list[AppSpace]:
    """Return the app window's spaces on this machine; raise WorkspaceError when no window is open."""
    records = _app_json("herdr-app", "ls").get("spaces")
    if not isinstance(records, list):
        raise WorkspaceError("herdr-app ls returned no spaces")

    spaces: list[AppSpace] = []
    for record in _objects(records):
        if record.get("machine") is not None:
            continue
        terminals = [
            _string(terminal.get("terminal"))
            for tab in _objects(record.get("tabs"))
            for terminal in _objects(tab.get("terminals"))
        ]
        spaces.append(
            AppSpace(
                space_id=_string(record.get("id")),
                folder=_string(record.get("folder")),
                is_shown=record.get("active") is True,
                first_terminal=terminals[0] if len(terminals) > 0 else "",
            )
        )
    return spaces


def _app_space_live_folder(space: AppSpace) -> str:
    """Return where SPACE is now: its first terminal's folder, else the folder it was made in.

    Falls back to ``space.folder`` when the space shows no terminal or hc
    reports no folder for it; returns "" when neither is known. Raises
    WorkspaceError when hc fails.
    """
    if space.first_terminal != "":
        folder = _terminal_folder(space.first_terminal)
        if folder != "":
            return folder
    return space.folder


def _app_primary_space_id(primary_root: Path) -> str:
    """Return the first space now in the primary checkout PRIMARY_ROOT, or "" when there is none.

    A space counts when its live folder (see ``_app_space_live_folder``) is
    PRIMARY_ROOT or a folder inside it that no other jj workspace claims.
    Raises WorkspaceError when hc fails.
    """
    for space in _app_spaces():
        folder = _app_space_live_folder(space)
        checkout = find_jj_checkout(Path(folder)) if folder != "" else None
        if checkout is not None and checkout.root.resolve() == primary_root.resolve():
            return space.space_id
    return ""


def _select_app_space_or_warn(space_id: str) -> None:
    try:
        _ = _app_json("herdr-app", "do", "space.select", json.dumps({"id": space_id}))
    except WorkspaceError as error:
        print(f"warning: {error}", file=sys.stderr)


def _app_json(program: str, *arguments: str) -> dict[str, object]:
    """Return the JSON object PROGRAM, herdr-app or hc found on PATH, prints for ARGUMENTS.

    Raises WorkspaceError when it fails, for example ``herdr-app`` with no app
    window open, or prints no JSON.
    """
    command = [program, *arguments]
    result = _run(command)
    if result.returncode != 0:
        detail = _app_failure_detail(result)
        raise WorkspaceError(f"{shlex.join(command)} failed" + (f": {detail}" if detail != "" else ""))
    try:
        return _object(cast(object, json.loads(result.stdout)))
    except json.JSONDecodeError as error:
        raise WorkspaceError(f"{shlex.join(command)} returned malformed JSON") from error


def _app_failure_detail(result: subprocess.CompletedProcess[str]) -> str:
    """Return why a herdr-app or hc call failed, from its stderr or else its stdout.

    herdr-app replies ``{"error": MESSAGE}`` and hc ``{"error": {"message":
    MESSAGE, ...}}``; the message is used when present, otherwise the output
    as written.
    """
    output = result.stderr.strip()
    if output == "":
        output = result.stdout.strip()
    try:
        reply = _object(cast(object, json.loads(output)))
    except json.JSONDecodeError:
        return output
    error = reply.get("error")
    message = _string(error) if isinstance(error, str) else _string(_object(error).get("message"))
    return message if message != "" else output


def _objects(value: object) -> list[dict[str, object]]:
    """Return VALUE's objects when it is a list, each non-object as empty; else no objects."""
    return [_object(item) for item in cast(list[object], value)] if isinstance(value, list) else []


def _command_add(arguments: argparse.Namespace) -> int:
    name = cast(str, arguments.name)
    validate_name(name)
    workspace_id = cast(str | None, arguments.workspace)
    revision = cast(str, arguments.revision)
    focus = cast(bool, arguments.focus)
    if _host(arguments) == "app":
        folder = app_space_folder(workspace_id) if workspace_id is not None else Path.cwd()
        print(json.dumps(app_create(resolve_app_source(folder), name, revision=revision, focus=focus)))
        return 0

    source = resolve_source(_caller_workspace(workspace_id))
    print(json.dumps(create(source, name, revision=revision, focus=focus)))
    return 0


def _command_remove(arguments: argparse.Namespace) -> int:
    workspace_id = cast(str | None, arguments.workspace)
    dry_run = cast(bool, arguments.dry_run)
    focus = cast(bool, arguments.focus)
    if _host(arguments) == "app":
        app_target = resolve_app_target(workspace_id if workspace_id is not None else app_caller_space())
        summary = describe_removal(app_target.checkout)
        print(summary if dry_run else app_remove(app_target, focus=focus))
        return 0

    target = resolve_target(_caller_workspace(workspace_id))
    summary = describe_removal(target.checkout)
    if dry_run:
        print(summary)
        return 0
    print(remove(target, focus=focus))
    return 0


def _command_prompt_add(arguments: argparse.Namespace) -> int:
    pick = cast(bool, arguments.pick)
    first = cast(Path | None, arguments.first)
    if first is not None and not pick:
        raise WorkspaceError("--first needs --pick")
    if _host(arguments) == "app":
        app_source = pick_app_source(first) if pick else resolve_app_source(Path.cwd())
        if app_source is None:
            return 0
        print(f"New jj workspace for {app_source.primary_root.name}\n")
        name = input("Name: ")
        validate_name(name)
        revision = pick_base(app_source.primary_root)
        if revision is None:
            return 0
        _ = app_create(app_source, name, revision=revision, focus=True)
        return 0

    if pick:
        raise WorkspaceError("--pick needs the app host")
    source = resolve_source(_plugin_workspace())
    print(f"New jj workspace for {source.repo_name}\n")
    name = input("Name: ")
    validate_name(name)
    revision = pick_base(source.repo_root)
    if revision is None:
        return 0
    _ = create(source, name, revision=revision, focus=True)
    return 0


def _command_prompt_remove(arguments: argparse.Namespace) -> int:
    workspace_id = cast(str | None, arguments.workspace)
    if _host(arguments) == "app":
        app_target = resolve_app_target(workspace_id if workspace_id is not None else app_caller_space())
        if _confirm_removal(app_target.checkout, "app space"):
            _ = app_remove(app_target, focus=True)
        return 0

    target = resolve_target(workspace_id if workspace_id is not None else _plugin_workspace())
    if _confirm_removal(target.checkout, "workspace"):
        _ = remove(target, focus=True)
    return 0


def _confirm_removal(checkout: Path, closed: str) -> bool:
    """Show jjx's description of removing CHECKOUT and ask whether to go ahead.

    CLOSED names what removal closes in Herdr: a workspace, or an app space.
    """
    print(describe_removal(checkout) + "\n")
    print(f"This deletes the directory and closes its Herdr {closed}.")
    print("jj snapshots its working copy into a commit first; ignored files are lost.\n")
    return input("Remove? [y/N] ") in ("y", "Y")


def _host(arguments: argparse.Namespace) -> Host:
    chosen = cast(Host | None, arguments.host)
    return chosen if chosen is not None else default_host()


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
        help="create a jj workspace from trunk or another revision and open it in Herdr",
        description=(
            "Create jj workspace NAME from --revision REV, trunk() by default, in "
            "~/.herdr/worktrees/REPO/NAME "
            "for the repository of a Herdr workspace, which may show any of its "
            "checkouts, and open it in Herdr grouped under the primary checkout's "
            "workspace. In the app, the repository is the working directory's "
            "unless --workspace names a space, and NAME opens as a new space. "
            "Prints the new checkout's path and the Herdr workspace_id and "
            "pane_id showing it as JSON; in the app they are the space ID and its "
            "terminal's address."
        ),
    )
    _ = add.add_argument("name", metavar="NAME", help="workspace and directory name")
    _ = add.add_argument(
        "--revision",
        metavar="REV",
        default=DEFAULT_REVISION,
        help=f"jj revision the workspace starts on top of, such as a bookmark (default: {DEFAULT_REVISION})",
    )
    _add_workspace_option(
        add,
        "workspace whose repository to use",
        "the calling pane's: $HERDR_WORKSPACE_ID, or in the app the working directory",
    )
    _add_focus_option(add)
    _add_host_option(add)
    add.set_defaults(handler=_command_add)

    remove_parser = commands.add_parser(
        "remove",
        help="remove a Herdr workspace's jj workspace and close it",
        description=(
            "Remove the jj workspace a Herdr workspace shows with jjx workspace "
            "remove, which snapshots its working copy into a commit and deletes "
            "the directory, then close the Herdr workspace. Primary checkouts and "
            "Git worktrees are refused. In the app, the checkout is where the "
            "space's first terminal is now."
        ),
    )
    _add_workspace_option(remove_parser, "workspace to remove", _CALLER_WORKSPACE)
    _add_focus_option(remove_parser)
    _add_host_option(remove_parser)
    _ = remove_parser.add_argument(
        "--dry-run", action="store_true", help="report what would be removed and change nothing"
    )
    remove_parser.set_defaults(handler=_command_remove)

    prompt_add = commands.add_parser(
        "prompt-add",
        help="popup for add that asks for the base revision, from the working directory in the app",
        description=(
            "Ask for the new jj workspace's name, then in fzf for its base: "
            "trunk(), listed first so Enter keeps it, or a local bookmark. "
            "Closing fzf creates nothing."
        ),
    )
    _add_host_option(prompt_add)
    _ = prompt_add.add_argument(
        "--pick",
        action="store_true",
        help=(
            "in the app, choose the repository in fzf among those of the spaces "
            "on this machine instead of using the working directory"
        ),
    )
    _ = prompt_add.add_argument(
        "--first",
        metavar="FOLDER",
        type=Path,
        help="with --pick, list FOLDER's repository first, so Enter with an empty query picks it",
    )
    prompt_add.set_defaults(handler=_command_prompt_add, popup=True)

    prompt_remove = commands.add_parser("prompt-remove", help="popup for remove")
    _add_workspace_option(
        prompt_remove,
        "workspace to remove",
        "the plugin's current workspace, or in the app the calling pane's space",
    )
    _add_host_option(prompt_remove)
    prompt_remove.set_defaults(handler=_command_prompt_remove, popup=True)

    popup = commands.add_parser("open-popup", help="plugin action that opens a popup pane")
    _ = popup.add_argument("entrypoint", metavar="ENTRYPOINT")
    popup.set_defaults(handler=_command_open_popup)
    return parser


_CALLER_WORKSPACE = "the calling pane's: $HERDR_WORKSPACE_ID, or in the app the space of terminal $HC_TERMINAL_ID"


def _add_workspace_option(parser: argparse.ArgumentParser, workspace_help: str, default_help: str) -> None:
    _ = parser.add_argument(
        "--workspace",
        metavar="ID",
        help=f"Herdr {workspace_help}; in the app, a space ID (default: {default_help})",
    )


def _add_focus_option(parser: argparse.ArgumentParser) -> None:
    _ = parser.add_argument(
        "--focus", action="store_true", help="move the user's Herdr focus to the result"
    )


def _add_host_option(parser: argparse.ArgumentParser) -> None:
    _ = parser.add_argument(
        "--host",
        choices=HOSTS,
        help=(
            "the Herdr to drive: tui, the terminal UI, or app, the desktop app "
            "(default: app in an app terminal, where $HC_TERMINAL_ID is set and "
            "$HERDR_ENV is not 1; else tui)"
        ),
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
