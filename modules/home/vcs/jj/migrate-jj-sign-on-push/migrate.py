#!/usr/bin/env python3

"""Rewrite jj's deprecated ``git.sign-on-push`` in per-repository configs.

jj 0.47 deprecates the boolean ``git.sign-on-push`` in favor of the
``revsets.git-sign-on-push`` revset and warns on every command while a config
still sets it. Earlier jjx versions wrote the old key into each workspace's
repository config, ``<REPOS_DIR>/<id>/config.toml``. This rewrites ``true`` to
``"~signed() & mine()"`` and ``false`` to ``"none()"``, the revsets jj maps them
to, and keeps a ``revsets.git-sign-on-push`` the file already sets.

Files are edited as text so comments and layout survive. An edit is written
only when the edited file parses to exactly the old settings minus
``git.sign-on-push``, plus the revset; any other file, including one that
sets the key in a shape the text edit does not recognize, is left unchanged
with a warning on standard error. Each changed file gets one line on standard
output, so a second run prints nothing.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import tempfile
import tomllib
from pathlib import Path

SIGN_ON_PUSH_LINE = re.compile(
    r"^[ \t]*sign-on-push[ \t]*=[ \t]*(?:true|false)[ \t]*(?:#[^\n]*)?(?:\n|\Z)",
    re.MULTILINE,
)
REVSETS_HEADER_LINE = re.compile(
    r"^[ \t]*\[[ \t]*revsets[ \t]*\][ \t]*(?:#[^\n]*)?\n", re.MULTILINE
)


def main(arguments: list[str]) -> int:
    """Migrate every ``*/config.toml`` under REPOS_DIR; a missing directory is a no-op."""
    parser = argparse.ArgumentParser(
        prog="migrate-jj-sign-on-push",
        description="Rewrite git.sign-on-push to revsets.git-sign-on-push in jj repository configs.",
    )
    _ = parser.add_argument("repos_dir", metavar="REPOS_DIR", type=Path)
    repos_dir: Path = parser.parse_args(arguments).repos_dir

    if not repos_dir.is_dir():
        return 0

    for config_path in sorted(repos_dir.glob("*/config.toml")):
        migrate_repo_config(config_path)
    return 0


def migrate_repo_config(config_path: Path) -> None:
    """Rewrite one config file in place when it sets ``git.sign-on-push``.

    Prints one line when the file changes and warns on standard error when it
    sets the key but cannot be migrated safely; never raises for a bad file.
    """
    try:
        old_text = config_path.read_bytes().decode("utf-8")
        old_settings = tomllib.loads(old_text)
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
        warn(config_path, f"could not read config: {error}")
        return

    git_settings = old_settings.get("git")
    if not isinstance(git_settings, dict) or "sign-on-push" not in git_settings:
        return
    signs_on_push: object = git_settings["sign-on-push"]
    old_revsets = old_settings.get("revsets", {})
    if not isinstance(signs_on_push, bool) or not isinstance(old_revsets, dict):
        warn(config_path, "unexpected git.sign-on-push or revsets value; left unchanged")
        return

    # None when the file already sets the revset, which then wins over the old key.
    added_revset = (
        None
        if "git-sign-on-push" in old_revsets
        else "~signed() & mine()" if signs_on_push else "none()"
    )
    expected_settings = expected_migrated_settings(
        old_settings, git_settings, old_revsets, added_revset
    )
    new_text = migrated_text(old_text, added_revset)
    try:
        new_settings = tomllib.loads(new_text)
    except tomllib.TOMLDecodeError:
        new_settings = None
    if new_settings != expected_settings:
        warn(
            config_path,
            "git.sign-on-push is not set as a plain line under [git]; left unchanged",
        )
        return

    try:
        write_atomic(config_path, new_text)
    except OSError as error:
        warn(config_path, f"could not write config: {error}")
        return

    removed = f"removed git.sign-on-push = {str(signs_on_push).lower()}"
    if added_revset is None:
        print(f"{config_path}: {removed}, kept the existing revsets.git-sign-on-push")
    else:
        print(f'{config_path}: {removed}, set revsets.git-sign-on-push = "{added_revset}"')


def expected_migrated_settings(
    old_settings: dict[str, object],
    old_git_settings: dict[str, object],
    old_revsets: dict[str, object],
    added_revset: str | None,
) -> dict[str, object]:
    """Return the settings a correct migration of ``old_settings`` parses to."""
    expected_settings = old_settings | {
        "git": {
            key: value
            for key, value in old_git_settings.items()
            if key != "sign-on-push"
        },
    }
    if added_revset is not None:
        expected_settings["revsets"] = old_revsets | {"git-sign-on-push": added_revset}
    return expected_settings


def migrated_text(old_text: str, added_revset: str | None) -> str:
    """Remove the first ``sign-on-push`` line and add ``added_revset`` if given.

    The revset goes at the top of an existing ``[revsets]`` table, or into a new
    table appended at the end. The result is unverified; callers compare its
    parsed settings with ``expected_migrated_settings``.
    """
    new_text = SIGN_ON_PUSH_LINE.sub("", old_text, count=1)
    if added_revset is None:
        return new_text

    revset_line = f'git-sign-on-push = "{added_revset}"\n'
    if not new_text.endswith("\n"):
        new_text += "\n"
    header = REVSETS_HEADER_LINE.search(new_text)
    if header is not None:
        return new_text[: header.end()] + revset_line + new_text[header.end() :]
    return new_text.rstrip("\n") + "\n\n[revsets]\n" + revset_line


def write_atomic(path: Path, content: str) -> None:
    """Replace ``path`` with ``content`` atomically, keeping its file mode."""
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary_path = Path(temporary_name)

    try:
        with os.fdopen(descriptor, "wb") as temporary_file:
            _ = temporary_file.write(content.encode("utf-8"))
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        shutil.copymode(path, temporary_path)
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def warn(config_path: Path, message: str) -> None:
    """Report a config file the migration skipped."""
    print(f"migrate-jj-sign-on-push: {config_path}: {message}", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
