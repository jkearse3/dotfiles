"""Validate or create a jj workspace for an existing Git checkout.

Git gives every linked worktree a private Git directory below the primary
repository's ``.git/worktrees`` directory. jj can use that private directory
as its Git backend, which gives each linked worktree an independent jj
workspace while all worktrees continue to share the Git object database.
This is an unsupported jj compatibility mechanism, so this module validates
the relationship conservatively instead of treating path names as proof of
identity.

The normal path through :func:`ensure` preserves an existing compatible
``.jj`` and the working copy. A compatible legacy linked workspace may gain
the identity marker described below, but its jj state is not reinitialized.
New primary checkouts use colocated initialization; new linked worktrees point
jj at their private Git directory. For linked worktrees, an identity marker in
that private directory records the authenticated attachment target. It is
created during initialization or legacy enrollment and advances only after a
successful relocation repair.

The only repair performed here addresses a specific relocation case: moving
the primary repository makes a linked workspace's jj ``git_target`` stale.
After the caller runs ``git worktree repair``, Git can identify the linked
worktree's new private directory. This module rewrites ``git_target`` only if
Git's current registration, the marker, the stale target, and the expected Git
directory layout all agree. It then validates the repaired repository and
attempts to restore the stale target if validation fails, reporting both
errors if restoration also fails. It never repairs Git registration, recreates
an existing jj repository, or modifies working-copy files.

After a checkout is validated or initialized, its commit identity is mirrored
from Git into repository-local jj configuration. Git already resolves the
correct identity for every worktree through ``includeIf gitdir:`` conditions,
which key off the private Git directory below the primary repository; jj scopes
instead key off the workspace checkout path, so a worktree checked out beneath
an unrelated directory would otherwise fall back to jj's default identity. This
module reads Git's resolved ``user.name``, ``user.email``, and SSH signing
selection for the checkout and writes them to the workspace's ``--repo`` jj
config so jj agrees with Git wherever the checkout lives. For a freshly
initialized workspace whose empty working-copy commit still carries jj's default
author, the author is realigned once; a pre-existing workspace's commits are
never rewritten.
"""

from __future__ import annotations

import argparse
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import NoReturn, cast


class EnsureError(Exception):
    """A concise, user-facing validation or initialization failure."""


@dataclass(frozen=True)
class GitCheckout:
    """Canonical paths and worktree kind reported by Git for one checkout.

    ``git_dir`` is the checkout-specific Git directory. For a primary
    checkout it is also ``common_git_dir``; for a linked worktree it is the
    private ``.git/worktrees/<name>`` directory while ``common_git_dir`` is
    the primary repository's ``.git`` directory.
    """

    root: Path
    git_dir: Path
    common_git_dir: Path
    primary: bool


@dataclass(frozen=True)
class GitIdentity:
    """The commit identity Git resolves for a checkout, mirrored into jj.

    ``signing_key`` is ``None`` when Git would not SSH-sign this checkout's
    commits; that maps to jj's ``signing.backend = "none"``. A non-null value is
    the signing key selector, mapping to jj's ``ssh`` backend and that key.
    """

    name: str
    email: str
    signing_key: str | None


class Action(Enum):
    """A mutation that execution would perform, or an established no-op."""

    NONE = "no changes: compatible jj workspace at {root}"
    INITIALIZE_PRIMARY = "would initialize colocated jj workspace at {root}"
    INITIALIZE_LINKED = "would initialize linked jj workspace at {root} using {git_dir}"
    ENROLL = "would create linked-worktree identity marker {identity}"
    REPAIR = "would repair eligible stale jj target from {stale} to {git_dir}; post-write validation not run"


@dataclass(frozen=True)
class Plan:
    """The single action selected by read-only discovery and safety checks."""

    checkout: GitCheckout
    action: Action
    stale: Path | None = None
    git_identity: GitIdentity | None = None

    def describe(self) -> str:
        """Render the plan for a human; wording is not a machine interface."""
        text = self.action.value.format(
            root=self.checkout.root,
            git_dir=self.checkout.git_dir,
            identity=_identity_file(self.checkout),
            stale=self.stale,
        )
        if self.git_identity is not None:
            signing = "enabled" if self.git_identity.signing_key is not None else "disabled"
            text += f"; would mirror jj commit identity {self.git_identity.email} (signing {signing})"
        return text


def _run(command: Sequence[str], *, cwd: Path | None = None) -> bytes:
    """Run a command without a shell and return its stdout verbatim.

    stderr and process-launch failures become :class:`EnsureError` so callers
    can present one concise CLI error without leaking ``subprocess`` details.
    """
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise EnsureError(f"could not run {command[0]}: {error}") from error
    if result.returncode != 0:
        detail = os.fsdecode(result.stderr).strip()
        suffix = f": {detail}" if detail else ""
        raise EnsureError(f"{' '.join(command)} failed{suffix}")
    return result.stdout


def _line(command: Sequence[str], *, cwd: Path | None = None) -> str:
    """Run a command that must return exactly one non-empty newline-ended line."""
    output = _run(command, cwd=cwd)
    if not output.endswith(b"\n") or b"\n" in output[:-1] or not output[:-1]:
        raise EnsureError(f"{' '.join(command)} returned invalid output")
    return os.fsdecode(output[:-1])


def _reject_git_lfs(checkout: GitCheckout) -> None:
    """Reject checkouts whose active attribute files configure the LFS filter."""
    attribute_files: list[Path] = []
    for directory, names, _files in os.walk(checkout.root):
        path = Path(directory)
        if path != checkout.root and (path / ".git").exists():
            names.clear()
            continue
        names[:] = [name for name in names if name not in {".git", ".jj"}]
        attribute_files.append(path / ".gitattributes")
    attribute_files.extend(
        {
            checkout.git_dir / "info" / "attributes",
            checkout.common_git_dir / "info" / "attributes",
        }
    )
    configured = subprocess.run(
        ["git", "-C", os.fspath(checkout.root), "config", "--path", "--get", "core.attributesFile"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if configured.returncode == 0:
        value = os.fsdecode(configured.stdout).strip()
        if not value or "\n" in value:
            raise EnsureError("git config core.attributesFile returned invalid output")
        configured_path = Path(value).expanduser()
        attribute_files.append(
            configured_path if configured_path.is_absolute() else checkout.root / configured_path
        )
    elif configured.returncode != 1:
        detail = os.fsdecode(configured.stderr).strip()
        suffix = f": {detail}" if detail else ""
        raise EnsureError(f"could not inspect Git attribute configuration{suffix}")
    else:
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        attribute_files.append(config_home / "git" / "attributes")
    git_prefix = Path(_line(["git", "--exec-path"])).parent.parent
    attribute_files.append(git_prefix / "etc" / "gitattributes")
    for path in attribute_files:
        try:
            lines = path.read_text(errors="surrogateescape").splitlines()
        except FileNotFoundError:
            continue
        except OSError as error:
            raise EnsureError(f"could not inspect Git attributes at {path}: {error}") from error
        for line in lines:
            fields = line.split()
            if fields and not fields[0].startswith("#") and "filter=lfs" in fields[1:]:
                raise EnsureError(
                    f"Git LFS is not supported by jj; refusing checkout configured by {path}"
                )


def _existing_path(value: str, *, relative_to: Path) -> Path:
    """Resolve command-produced path text to a canonical existing path."""
    path = Path(value)
    try:
        return (path if path.is_absolute() else relative_to / path).resolve(strict=True)
    except (OSError, ValueError) as error:
        raise EnsureError(f"command returned an unusable path: {value}") from error


def _git_path(start: Path, argument: str) -> Path:
    """Return a canonical path from one path-valued ``git rev-parse`` query."""
    return _existing_path(
        _line(["git", "-C", os.fspath(start), "rev-parse", argument]),
        relative_to=start,
    )


def _same_file(first: Path, second: Path, message: str) -> None:
    """Require two paths to identify the same filesystem object."""
    try:
        matches = os.path.samefile(first, second)
    except OSError as error:
        raise EnsureError(f"{message}: {error}") from error
    if not matches:
        raise EnsureError(message)


def _worktree_paths(root: Path) -> list[Path]:
    """Parse the absolute worktree paths from Git's NUL-delimited metadata."""
    output = _run(["git", "-C", os.fspath(root), "worktree", "list", "--porcelain", "-z"])
    paths: list[Path] = []
    for record in output.split(b"\0\0"):
        if not record:
            continue
        fields: dict[bytes, bytes] = {}
        for line in record.strip(b"\0").split(b"\0"):
            key, separator, value = line.partition(b" ")
            if separator:
                fields[key] = value
        try:
            path = Path(os.fsdecode(fields[b"worktree"]))
        except (KeyError, UnicodeError) as error:
            raise EnsureError("git returned malformed worktree metadata") from error
        if not path.is_absolute():
            raise EnsureError("git returned a relative worktree path")
        paths.append(path)
    return paths


def discover(start: Path) -> GitCheckout:
    """Discover and authenticate the Git checkout containing ``start``.

    A checkout must appear exactly once in ``git worktree list``. For linked
    worktrees, the private Git directory obtained through the checkout must
    also match the directory obtained through that registration. These checks
    prevent stale or ambiguous Git metadata from becoming input to jj repair.
    """
    root = _git_path(start, "--show-toplevel")
    git_dir = _git_path(root, "--absolute-git-dir")
    common_git_dir = _git_path(root, "--git-common-dir")
    matches: list[Path] = []
    for path in _worktree_paths(root):
        try:
            if os.path.samefile(path, root):
                matches.append(path)
        except OSError:
            continue
    if len(matches) != 1:
        raise EnsureError("Git checkout is not uniquely registered as a worktree")
    primary = os.path.samefile(git_dir, common_git_dir)
    if not primary:
        registered_git = _git_path(matches[0], "--absolute-git-dir")
        _same_file(
            registered_git,
            git_dir,
            "registered worktree does not use the discovered private Git directory",
        )
    return GitCheckout(root, git_dir, common_git_dir, primary)


def _jj_path(root: Path, *arguments: str) -> Path:
    """Run a read-only jj path query without snapshotting the working copy."""
    value = _line(
        [
            "jj",
            "--no-pager",
            "--color=never",
            "--ignore-working-copy",
            "-R",
            os.fspath(root),
            *arguments,
        ]
    )
    return _existing_path(value, relative_to=root)


def _validate(checkout: GitCheckout) -> None:
    """Require jj to use this checkout root and its exact Git directory."""
    _same_file(_jj_path(checkout.root, "root"), checkout.root, "jj root does not match Git checkout")
    _same_file(
        _jj_path(checkout.root, "git", "root"),
        checkout.git_dir,
        "jj repository does not use this checkout's Git directory",
    )


def _git_target(checkout: GitCheckout) -> Path:
    """Return jj's file containing the path to its Git backend."""
    return checkout.root / ".jj" / "repo" / "store" / "git_target"


def _identity_file(checkout: GitCheckout) -> Path:
    """Return the jj-ensure ownership marker in a worktree's private Git dir."""
    return checkout.git_dir / "jj-ensure-target"


def _ensure_identity(checkout: GitCheckout) -> None:
    """Create or validate the linked-worktree attachment identity.

    Creation is exclusive so an existing marker is never overwritten. The
    marker contains the exact private Git directory as raw filesystem bytes.
    If writing or syncing a newly created marker fails, only that marker is
    removed, allowing a later invocation to retry safely.
    """
    path = _identity_file(checkout)
    expected = os.fsencode(checkout.git_dir)
    created = False
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        created = True
        with os.fdopen(descriptor, "wb") as identity:
            _ = identity.write(expected)
            identity.flush()
            os.fsync(identity.fileno())
    except FileExistsError:
        try:
            mode = path.lstat().st_mode
            actual = path.read_bytes()
        except OSError as error:
            raise EnsureError(f"could not inspect jj-ensure attachment identity: {error}") from error
        if not stat.S_ISREG(mode) or stat.S_ISLNK(mode) or actual != expected:
            raise EnsureError("Git worktree has an incompatible jj-ensure attachment identity")
    except OSError as error:
        cleanup_error: OSError | None = None
        if created:
            try:
                path.unlink()
            except OSError as failure:
                cleanup_error = failure
        suffix = f"; cleanup failed: {cleanup_error}" if cleanup_error is not None else ""
        raise EnsureError(f"could not record jj-ensure attachment identity: {error}{suffix}") from error


def _has_identity(checkout: GitCheckout) -> bool:
    """Return whether a valid identity exists, without creating or changing it."""
    path = _identity_file(checkout)
    try:
        mode = path.lstat().st_mode
        actual = path.read_bytes()
    except FileNotFoundError:
        return False
    except OSError as error:
        raise EnsureError(f"could not inspect jj-ensure attachment identity: {error}") from error
    if not stat.S_ISREG(mode) or stat.S_ISLNK(mode) or actual != os.fsencode(checkout.git_dir):
        raise EnsureError("Git worktree has an incompatible jj-ensure attachment identity")
    return True


def _read_identity(checkout: GitCheckout) -> Path:
    """Read a regular, absolute attachment identity for relocation repair."""
    path = _identity_file(checkout)
    try:
        mode = path.lstat().st_mode
        data = path.read_bytes()
    except OSError as error:
        raise EnsureError(
            f"cannot establish relocation identity; reinitialize the linked jj workspace manually: {error}"
        ) from error
    if not stat.S_ISREG(mode) or stat.S_ISLNK(mode):
        raise EnsureError("jj-ensure attachment identity is malformed; leaving .jj unchanged")
    try:
        git_dir = Path(os.fsdecode(data))
    except (UnicodeError, ValueError) as error:
        raise EnsureError("jj-ensure attachment identity is malformed; leaving .jj unchanged") from error
    if not data or not git_dir.is_absolute():
        raise EnsureError("jj-ensure attachment identity is malformed; leaving .jj unchanged")
    return git_dir


def _read_stale_target(checkout: GitCheckout) -> Path:
    """Read a syntactically valid jj target that no longer exists.

    An existing target means the jj workspace points somewhere real but
    incompatible, which is not evidence of relocation and must not be
    rewritten automatically.
    """
    target_file = _git_target(checkout)
    try:
        mode = target_file.lstat().st_mode
        data = target_file.read_bytes()
    except OSError as error:
        raise EnsureError(f"cannot inspect incompatible jj Git target: {error}") from error
    if not stat.S_ISREG(mode) or stat.S_ISLNK(mode):
        raise EnsureError("incompatible jj Git target is not a regular file")
    try:
        value = os.fsdecode(data).strip()
        stale = Path(value)
    except (UnicodeError, ValueError) as error:
        raise EnsureError("incompatible jj Git target is malformed") from error
    if not value or data not in {os.fsencode(value), os.fsencode(value) + b"\n"} or not stale.is_absolute():
        raise EnsureError("incompatible jj Git target is malformed")
    if stale.exists():
        raise EnsureError("existing jj repository uses a different Git directory")
    return stale


def _validate_relocation(checkout: GitCheckout, stale: Path) -> None:
    """Prove that ``stale`` and the current Git directory are relocation peers.

    Repair is restricted to linked worktrees. The old target must equal the
    recorded identity, both old and new paths must end in the same
    ``worktrees/<name>`` pair, and the new pair must belong to Git's currently
    discovered common directory. No individual check is sufficient alone;
    together they constrain repair to a primary-repository relocation.
    """
    if checkout.primary:
        raise EnsureError("existing primary jj repository is incompatible")
    if _read_identity(checkout) != stale:
        raise EnsureError("stale jj target does not match this workspace's recorded attachment identity")
    expected_suffix = ("worktrees", checkout.git_dir.name)
    if len(stale.parts) < 2 or stale.parts[-2:] != expected_suffix:
        raise EnsureError("stale jj target does not identify this Git worktree")
    if checkout.git_dir.parts[-2:] != expected_suffix:
        raise EnsureError("current private Git directory has an unexpected layout")
    if stale.parent.parent.name != ".git" or checkout.git_dir.parent.parent != checkout.common_git_dir:
        raise EnsureError("stale jj target cannot be tied to the current repository")


def _write_target_atomic(path: Path, value: Path) -> None:
    """Durably stage ``value`` beside ``path`` and atomically replace ``path``.

    Keeping the temporary file in the target directory ensures ``os.replace``
    does not cross filesystems. A failure before replacement leaves the
    original target intact and removes the temporary file.
    """
    descriptor: int | None = None
    temporary: Path | None = None
    try:
        descriptor, name = tempfile.mkstemp(prefix=".git_target.", dir=path.parent)
        temporary = Path(name)
        _ = os.write(descriptor, os.fsencode(value))
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = None
        os.replace(temporary, path)
        temporary = None
    except OSError as error:
        raise EnsureError(f"could not atomically repair jj Git target: {error}") from error
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _repair(checkout: GitCheckout) -> None:
    """Repair a proven stale linked-worktree target and validate the result.

    Validation after replacement checks both jj and a fresh Git discovery.
    Once those agree, the identity marker advances to the new private Git
    directory so a later relocation can be authenticated against this one. If
    validation fails, restoration of the stale target is attempted; a failure
    of that rollback is reported alongside the original validation error.
    """
    stale = _read_stale_target(checkout)
    _validate_relocation(checkout, stale)
    target_file = _git_target(checkout)
    original = target_file.read_bytes()
    _write_target_atomic(target_file, checkout.git_dir)
    try:
        _validate(checkout)
        refreshed = discover(checkout.root)
        _same_file(refreshed.git_dir, checkout.git_dir, "Git worktree identity changed during repair")
        _write_target_atomic(_identity_file(checkout), checkout.git_dir)
    except EnsureError as error:
        try:
            _write_target_atomic(target_file, Path(os.fsdecode(original).strip()))
        except EnsureError as rollback_error:
            raise EnsureError(f"repair validation failed: {error}; rollback failed: {rollback_error}") from error
        raise EnsureError(f"repair validation failed; restored stale target: {error}") from error


def _remove_created_jj(path: Path) -> str:
    """Remove initialization-created jj state and return any cleanup detail."""
    try:
        if path.is_symlink() or not path.is_dir():
            path.unlink(missing_ok=True)
        else:
            shutil.rmtree(path)
    except OSError as error:
        return f"; cleanup failed: {error}"
    return ""


def _git_config_value(root: Path, key: str, *, boolean: bool = False) -> str | None:
    """Return one Git config value for ``root``, or ``None`` when it is unset.

    ``git config --get`` exits 1 for a missing key; any other nonzero status is
    a real failure. ``boolean`` normalizes truthy spellings to ``true``/``false``.
    """
    command = ["git", "-C", os.fspath(root), "config"]
    if boolean:
        command.append("--type=bool")
    command.extend(["--get", key])
    result = subprocess.run(command, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode == 1:
        return None
    if result.returncode != 0:
        detail = os.fsdecode(result.stderr).strip()
        suffix = f": {detail}" if detail else ""
        raise EnsureError(f"could not read git config {key}{suffix}")
    value = os.fsdecode(result.stdout)
    return value[:-1] if value.endswith("\n") else value


def _git_identity(checkout: GitCheckout) -> GitIdentity | None:
    """Resolve Git's commit identity for the checkout, or ``None`` if incomplete.

    Signing is mirrored only for SSH-formatted signing with a selected key,
    matching this environment's configuration; any other shape maps to no jj
    signing rather than guessing an incompatible backend.
    """
    name = _git_config_value(checkout.root, "user.name")
    email = _git_config_value(checkout.root, "user.email")
    if not name or not email:
        return None
    signs = (
        _git_config_value(checkout.root, "commit.gpgSign", boolean=True) == "true"
        and _git_config_value(checkout.root, "gpg.format") == "ssh"
    )
    signing_key = _git_config_value(checkout.root, "user.signingKey") if signs else None
    return GitIdentity(name=name, email=email, signing_key=signing_key or None)


def _jj_config_set(checkout: GitCheckout, key: str, value: str) -> None:
    """Set one repository-local jj config value without snapshotting the tree."""
    _ = _run(
        [
            "jj",
            "--no-pager",
            "--color=never",
            "--ignore-working-copy",
            "-R",
            os.fspath(checkout.root),
            "config",
            "set",
            "--repo",
            key,
            value,
        ]
    )


def _apply_identity(checkout: GitCheckout, identity: GitIdentity) -> None:
    """Write Git's resolved identity into the workspace's repository-local jj config.

    ``config set`` records values without creating a jj operation, so this is
    safe to repeat on an already-compatible workspace. Signing reproduces the
    jj settings the identity policy would render: an SSH backend with the key
    and push-time signing when Git signs, or an inert backend otherwise.
    """
    settings: list[tuple[str, str]] = [
        ("user.name", identity.name),
        ("user.email", identity.email),
    ]
    if identity.signing_key is not None:
        settings += [
            ("signing.backend", "ssh"),
            ("signing.key", identity.signing_key),
            ("git.sign-on-push", "true"),
        ]
    else:
        settings += [
            ("signing.backend", "none"),
            ("git.sign-on-push", "false"),
        ]
    for key, value in settings:
        _jj_config_set(checkout, key, value)


def _align_working_copy_author(checkout: GitCheckout, identity: GitIdentity) -> None:
    """Realign a freshly initialized empty working-copy commit's author to ``identity``.

    jj fixes a commit's author at creation, so the empty working copy created
    during initialization keeps jj's default author until rewritten. Only an
    empty working-copy commit is realigned, so a workspace that already carries
    work is never rewritten; the author is left untouched when it already
    matches, avoiding a needless operation.
    """
    template = 'if(empty, "empty", "nonempty") ++ "\\n" ++ author.email() ++ "\\n" ++ author.name()'
    output = _run(
        [
            "jj",
            "--no-pager",
            "--color=never",
            "--ignore-working-copy",
            "-R",
            os.fspath(checkout.root),
            "log",
            "-r",
            "@",
            "--no-graph",
            "-T",
            template,
        ]
    )
    fields = os.fsdecode(output).split("\n")
    if len(fields) < 3:
        raise EnsureError("jj returned malformed working-copy author metadata")
    state, email, name = fields[0], fields[1], fields[2]
    if state != "empty" or (email == identity.email and name == identity.name):
        return
    _ = _run(
        [
            "jj",
            "--no-pager",
            "--color=never",
            "-R",
            os.fspath(checkout.root),
            "metaedit",
            "--update-author",
        ]
    )


def _stamp_identity(checkout: GitCheckout, *, fresh_init: bool) -> None:
    """Mirror Git's identity into jj, realigning a freshly created author once."""
    identity = _git_identity(checkout)
    if identity is None:
        return
    _apply_identity(checkout, identity)
    if fresh_init:
        _align_working_copy_author(checkout, identity)


def plan(start: Path | None = None) -> Plan:
    """Select the action :func:`ensure` would take without modifying the checkout.

    All discovery and pre-mutation safety checks are performed. Initialization
    and repair still require their normal post-write validation when executed,
    so a planned action is not a promise that execution will succeed.
    """
    checkout = discover(Path(".") if start is None else start)
    _reject_git_lfs(checkout)
    identity = _git_identity(checkout)
    jj_dir = checkout.root / ".jj"
    try:
        mode = jj_dir.lstat().st_mode
    except FileNotFoundError:
        action = Action.INITIALIZE_PRIMARY if checkout.primary else Action.INITIALIZE_LINKED
        return Plan(checkout, action, git_identity=identity)
    except OSError as error:
        raise EnsureError(f"could not inspect pre-existing .jj: {error}") from error
    if not stat.S_ISDIR(mode) or stat.S_ISLNK(mode):
        raise EnsureError("pre-existing .jj is not a compatible directory")
    try:
        _validate(checkout)
    except EnsureError:
        stale = _read_stale_target(checkout)
        _validate_relocation(checkout, stale)
        return Plan(checkout, Action.REPAIR, stale, git_identity=identity)
    if not checkout.primary and not _has_identity(checkout):
        return Plan(checkout, Action.ENROLL, git_identity=identity)
    return Plan(checkout, Action.NONE, git_identity=identity)


def ensure(start: Path | None = None) -> Path:
    """Ensure ``start`` belongs to a compatible jj-backed Git checkout.

    Existing compatible workspaces are preserved. An incompatible existing
    workspace is eligible only for the narrowly authenticated relocation
    repair; otherwise the command fails without replacing it. If no ``.jj``
    exists, initialization uses colocated mode for the primary checkout and
    the private Git directory for a linked worktree. Initialization failures
    remove only the ``.jj`` state created by this invocation.

    Returns the canonical Git worktree root.
    """
    checkout = discover(Path(".") if start is None else start)
    _reject_git_lfs(checkout)
    jj_dir = checkout.root / ".jj"
    try:
        mode = jj_dir.lstat().st_mode
    except FileNotFoundError:
        mode = None
    except OSError as error:
        raise EnsureError(f"could not inspect pre-existing .jj: {error}") from error
    if mode is not None:
        if not stat.S_ISDIR(mode) or stat.S_ISLNK(mode):
            raise EnsureError("pre-existing .jj is not a compatible directory")
        try:
            _validate(checkout)
        except EnsureError:
            _repair(checkout)
        if not checkout.primary:
            _ensure_identity(checkout)
        fresh_init = False
    else:
        command = ["jj", "git", "init"]
        if checkout.primary:
            command.append("--colocate")
        else:
            command.append(f"--git-repo={checkout.git_dir}")
        command.append(".")
        try:
            _ = _run(command, cwd=checkout.root)
            _validate(checkout)
            refreshed = discover(checkout.root)
            _same_file(refreshed.git_dir, checkout.git_dir, "Git worktree identity changed during initialization")
            if not checkout.primary:
                _ensure_identity(checkout)
        except EnsureError as error:
            suffix = _remove_created_jj(jj_dir)
            raise EnsureError(f"could not initialize jj repository: {error}{suffix}") from error
        fresh_init = True

    _stamp_identity(checkout, fresh_init=fresh_init)
    return checkout.root


def create_parser() -> argparse.ArgumentParser:
    """Build the command-line parser, including compatibility warnings."""
    parser = argparse.ArgumentParser(
        prog="jj-ensure",
        description="Ensure PATH is a valid jj workspace backed by its current Git checkout.",
        epilog=(
            "Linked Git worktrees use jj's unsupported private-Git-directory compatibility "
            "mechanism. Retest jj-ensure after jj upgrades. After moving a primary repository, "
            "run 'git worktree repair' first; jj-ensure can then repair the linked workspace's "
            "stale jj target without replacing its operation history."
        ),
    )
    _ = parser.add_argument("path", metavar="PATH", nargs="?", default=".")
    _ = parser.add_argument(
        "--dry-run",
        action="store_true",
        help="show the validated action without modifying the workspace",
    )
    return parser


def _exit_error(error: EnsureError) -> NoReturn:
    """Print one user-facing error and terminate with failure status."""
    print(f"error: {error}", file=sys.stderr)
    raise SystemExit(1)


def main(argv: list[str] | None = None) -> int:
    """Run the CLI and print the canonical ensured worktree root."""
    namespace = create_parser().parse_args(argv)
    try:
        path = Path(cast(str, namespace.path))
        if cast(bool, namespace.dry_run):
            print(plan(path).describe())
        else:
            print(ensure(path))
    except EnsureError as error:
        _exit_error(error)
    return 0
