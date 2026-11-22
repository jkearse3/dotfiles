#!/usr/bin/env python3
"""Copy the gitignored files a `.worktreeinclude` selects into a linked worktree.

A file is copied from the repository's primary worktree only when it matches a
pattern in that worktree's `.worktreeinclude` (gitignore syntax) and its own
ignore rules also ignore it. Tracked and merely untracked files are never copied,
and existing destination files are never overwritten.

In a primary checkout, a repository whose primary worktree is bare, or a
repository without `.worktreeinclude`, the command silently does nothing. With
`--post-checkout`, it runs as Git's post-checkout hook and populates the linked
worktree `git worktree add` just created.
"""

from __future__ import annotations

import argparse
import filecmp
import os
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from enum import Enum
from pathlib import Path


INCLUDE_FILE = ".worktreeinclude"
JJ_METADATA_PREFIX = b".jj/"
GIT = os.environ.get("WORKTREE_INCLUDE_GIT", "git")


class IncludeError(Exception):
    """A concise, user-facing failure."""


class CopyOutcome(Enum):
    """What happened, or would happen, to one selected file."""

    COPIED = "copied"
    WOULD_COPY = "would copy"
    UNCHANGED = "unchanged"
    KEPT_EXISTING = "kept existing"


def main() -> int:
    arguments = parse_arguments(sys.argv[1:])
    clear_git_environment()
    try:
        if arguments.post_checkout is not None:
            post_checkout(*arguments.post_checkout)
        else:
            populate(arguments.destination or Path.cwd(), dry_run=arguments.dry_run)
    except IncludeError as error:
        print(f"worktree-include: {error}", file=sys.stderr)
        return 1
    return 0


def post_checkout(previous_head: str, new_head: str, checkout_kind: str) -> None:
    """Handle Git's post-checkout hook, which runs in the checked-out worktree.

    Only a branch checkout from the null commit, which is what `git worktree
    add` performs, is populated; clones and ordinary checkouts are silently
    ignored.
    """
    del new_head
    if checkout_kind != "1" or previous_head.strip("0") != "":
        return
    populate(Path.cwd(), dry_run=False)


def populate(destination: Path, *, dry_run: bool) -> None:
    """Copy into the linked worktree containing DESTINATION from the primary
    worktree.

    A primary checkout, a repository whose primary worktree is bare, and a
    repository without an include file are silently left alone. Raises
    IncludeError when DESTINATION is not inside a Git worktree or a selected
    file cannot be copied.
    """
    destination_root = worktree_root(destination)
    if is_primary_checkout(destination_root):
        return
    source_root = primary_worktree(destination_root)
    if source_root is None:
        return
    include_patterns = source_root / INCLUDE_FILE
    if not include_patterns.is_file():
        return
    for relative_path in included_ignored_files(source_root, include_patterns):
        outcome = copy_included_file(source_root, destination_root, relative_path, dry_run=dry_run)
        report(outcome, relative_path)


def parse_arguments(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="worktree-include",
        description=(
            f"Copy gitignored files selected by the primary worktree's {INCLUDE_FILE} "
            "into a linked worktree of the same repository."
        ),
    )
    _ = parser.add_argument(
        "destination",
        nargs="?",
        type=Path,
        help="linked worktree to populate (default: the current directory's worktree)",
    )
    _ = parser.add_argument(
        "--dry-run",
        action="store_true",
        help="report what would be copied without writing anything",
    )
    _ = parser.add_argument(
        "--post-checkout",
        nargs=3,
        metavar=("PREVIOUS_HEAD", "NEW_HEAD", "CHECKOUT_KIND"),
        help="run as Git's post-checkout hook, populating newly added linked worktrees",
    )
    arguments = parser.parse_args(argv)
    if arguments.post_checkout is not None and (arguments.destination is not None or arguments.dry_run):
        parser.error("--post-checkout cannot be combined with other arguments")
    return arguments


def worktree_root(start: Path) -> Path:
    if not start.is_dir():
        raise IncludeError(f"not a directory: {start}")
    return Path(git_line("rev-parse", "--show-toplevel", cwd=start, failure=f"not inside a Git worktree: {start}"))


def is_primary_checkout(checkout: Path) -> bool:
    """Tell whether CHECKOUT is the repository's primary checkout rather than a
    linked worktree, by whether its Git directory is the common one. Unlike the
    path `git worktree list` reports, this also holds for a checkout whose Git
    directory was moved with `--separate-git-dir`."""
    output = git_line(
        "rev-parse",
        "--path-format=absolute",
        "--absolute-git-dir",
        "--git-common-dir",
        cwd=checkout,
    )
    git_dir, common_dir = output.split("\n", 1)
    return Path(git_dir).samefile(common_dir)


def primary_worktree(checkout: Path) -> Path | None:
    """Return the first worktree Git lists, which is the primary checkout, or
    None when the repository is bare and has no primary checkout."""
    output = git("worktree", "list", "--porcelain", "-z", cwd=checkout)
    fields = output.split(b"\0\0", 1)[0].split(b"\0")
    if not fields[0].startswith(b"worktree "):
        raise IncludeError("could not identify the primary Git worktree")
    if b"bare" in fields:
        return None
    return worktree_root(Path(os.fsdecode(fields[0].removeprefix(b"worktree "))))


def included_ignored_files(source: Path, include_patterns: Path) -> list[str]:
    """List untracked source paths that match INCLUDE_PATTERNS and that the
    source's standard ignore rules also ignore, in Git's order. Nested
    repositories, which Git lists as directories, and jj metadata under `.jj/`,
    which jj ignores itself, are skipped."""
    matching = git(
        "ls-files",
        "-z",
        "--others",
        "--ignored",
        f"--exclude-from={include_patterns}",
        cwd=source,
    )
    if matching == b"":
        return []

    ignored = git("check-ignore", "-z", "--stdin", cwd=source, stdin=matching, allowed_codes=(0, 1))
    return [
        os.fsdecode(path)
        for path in ignored.split(b"\0")
        if path != b"" and not path.endswith(b"/") and not path.startswith(JJ_METADATA_PREFIX)
    ]


def copy_included_file(source_root: Path, destination_root: Path, relative_path: str, *, dry_run: bool) -> CopyOutcome:
    """Copy one selected file, preserving symlinks as symlinks and never
    replacing an existing destination path. Any filesystem failure, including
    one while comparing with an existing destination, raises IncludeError."""
    source_path = source_root / relative_path
    destination_path = destination_root / relative_path

    try:
        if os.path.lexists(destination_path):
            if is_same_file_content(source_path, destination_path):
                return CopyOutcome.UNCHANGED
            return CopyOutcome.KEPT_EXISTING

        require_creatable_directory(destination_root, destination_path.parent)
        if dry_run:
            return CopyOutcome.WOULD_COPY

        try:
            destination_path.parent.mkdir(parents=True, exist_ok=True)
        except OSError as error:
            raise IncludeError(f"could not create {destination_path.parent}: {error}") from None
        copy_atomically(source_path, destination_path)
        return CopyOutcome.COPIED
    except OSError as error:
        raise IncludeError(f"could not copy {source_path} to {destination_path}: {error}") from None


def is_same_file_content(source_path: Path, destination_path: Path) -> bool:
    if source_path.is_symlink() or destination_path.is_symlink():
        return (
            source_path.is_symlink()
            and destination_path.is_symlink()
            and os.readlink(source_path) == os.readlink(destination_path)
        )
    return destination_path.is_file() and filecmp.cmp(source_path, destination_path, shallow=False)


def require_creatable_directory(root: Path, directory: Path) -> None:
    """Refuse DIRECTORY when its nearest existing path is not a directory, such
    as a regular file or a dangling symlink, or when it resolves outside ROOT,
    such as through a symlinked parent, so a copy can never fail midway or
    escape the destination worktree."""
    nearest_existing = directory
    while not os.path.lexists(nearest_existing):
        nearest_existing = nearest_existing.parent
    if not nearest_existing.is_dir():
        raise IncludeError(f"cannot create {directory}: {nearest_existing} is not a directory")
    if not nearest_existing.resolve().is_relative_to(root.resolve()):
        raise IncludeError(f"refusing to write outside the destination worktree: {directory}")


def copy_atomically(source_path: Path, destination_path: Path) -> None:
    """Copy into a staged sibling, symlinks as symlinks, and rename it into
    place, so a failed copy never leaves a partial file behind."""
    descriptor, staged = tempfile.mkstemp(prefix=f".{destination_path.name}.", dir=destination_path.parent)
    os.close(descriptor)
    staged_path = Path(staged)
    try:
        staged_path.unlink()
        _ = shutil.copy2(source_path, staged_path, follow_symlinks=False)
        os.replace(staged_path, destination_path)
    except OSError:
        staged_path.unlink(missing_ok=True)
        raise


def report(outcome: CopyOutcome, relative_path: str) -> None:
    if outcome is CopyOutcome.KEPT_EXISTING:
        print(
            f"worktree-include: kept existing {relative_path} (differs from source)",
            file=sys.stderr,
        )
    else:
        print(f"{outcome.value} {relative_path}")


def git(
    *arguments: str,
    cwd: Path,
    stdin: bytes | None = None,
    allowed_codes: tuple[int, ...] = (0,),
    failure: str | None = None,
) -> bytes:
    result = subprocess.run(
        (GIT, *arguments),
        cwd=cwd,
        input=stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode not in allowed_codes:
        if failure is not None:
            raise IncludeError(failure)
        detail = os.fsdecode(result.stderr).strip()
        raise IncludeError(f"git {arguments[0]} failed in {cwd}: {detail}")
    return result.stdout


def git_line(*arguments: str, cwd: Path, failure: str | None = None) -> str:
    return os.fsdecode(git(*arguments, cwd=cwd, failure=failure).removesuffix(b"\n"))


def clear_git_environment() -> None:
    """Drop repository-scoped variables such as GIT_DIR that a calling Git hook
    may export, so every command resolves its repository from its own cwd."""
    result = subprocess.run((GIT, "rev-parse", "--local-env-vars"), stdout=subprocess.PIPE)
    for variable in os.fsdecode(result.stdout).splitlines():
        _ = os.environ.pop(variable, None)


if __name__ == "__main__":
    raise SystemExit(main())
