#!/usr/bin/env python3

"""Repoint ``signing.key`` in per-repository jj configs from an old key path to a new one.

jjx copies git's ``user.signingKey`` into each workspace's repository config,
``<REPOS_DIR>/<id>/config.toml``, so those files keep the key path git had when
jjx last ran. When the signing key moves, jj fails to sign in every repository
whose config still names the old path. This rewrites ``signing.key`` from
exactly OLD_KEY to NEW_KEY and leaves every other value alone.

Files are edited as text so comments and layout survive. An edit is written
only when the edited file parses to exactly the old settings with
``signing.key`` replaced; any other file, including one that sets the key in a
shape the text edit does not recognize, is left unchanged with a warning on
standard error. Each changed file gets one line on standard output, so a second
run prints nothing.

While NEW_KEY does not exist, nothing is rewritten: a config naming a missing
key fails to sign just as one naming the old key does, and leaving it unchanged
keeps it working if the old key comes back. One line on standard error then
counts the configs still naming OLD_KEY, if any; the first run after NEW_KEY
exists rewrites them.
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


def main(arguments: list[str]) -> int:
    """Migrate every ``*/config.toml`` under REPOS_DIR; a missing directory is a no-op."""
    parser = argparse.ArgumentParser(
        prog="migrate-jj-signing-key",
        description="Rewrite signing.key from OLD_KEY to NEW_KEY in jj repository configs.",
    )
    _ = parser.add_argument("repos_dir", metavar="REPOS_DIR", type=Path)
    _ = parser.add_argument("old_key", metavar="OLD_KEY")
    _ = parser.add_argument("new_key", metavar="NEW_KEY")
    parsed = parser.parse_args(arguments)
    repos_dir: Path = parsed.repos_dir
    old_key: str = parsed.old_key
    new_key: str = parsed.new_key

    if not repos_dir.is_dir():
        return 0

    config_paths = sorted(repos_dir.glob("*/config.toml"))
    if not os.path.exists(new_key):
        waiting = [path for path in config_paths if signing_key_of(path) == old_key]
        if len(waiting) > 0:
            print(
                f"migrate-jj-signing-key: {new_key} does not exist yet; left {len(waiting)} repository "
                + f"config(s) naming {old_key} unchanged until a run after it does",
                file=sys.stderr,
            )
        return 0

    for config_path in config_paths:
        migrate_repo_config(config_path, old_key, new_key)
    return 0


def signing_key_of(config_path: Path) -> object:
    """Return a config's ``signing.key``, or None when it is unset or unreadable."""
    try:
        settings = tomllib.loads(config_path.read_bytes().decode("utf-8"))
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError):
        return None
    signing = settings.get("signing")
    return signing.get("key") if isinstance(signing, dict) else None


def migrate_repo_config(config_path: Path, old_key: str, new_key: str) -> None:
    """Rewrite one config file in place when its ``signing.key`` is ``old_key``.

    Prints one line when the file changes and warns on standard error when it
    names the old key but cannot be migrated safely; never raises for a bad file.
    """
    try:
        old_text = config_path.read_bytes().decode("utf-8")
        old_settings = tomllib.loads(old_text)
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
        warn(config_path, f"could not read config: {error}")
        return

    signing = old_settings.get("signing")
    if not isinstance(signing, dict) or signing.get("key") != old_key:
        return

    expected_settings = old_settings | {"signing": signing | {"key": new_key}}
    new_text = migrated_text(old_text, old_key, new_key)
    try:
        new_settings = tomllib.loads(new_text)
    except tomllib.TOMLDecodeError:
        new_settings = None
    if new_settings != expected_settings:
        warn(config_path, "signing.key is not set as a plain line under [signing]; left unchanged")
        return

    try:
        write_atomic(config_path, new_text)
    except OSError as error:
        warn(config_path, f"could not write config: {error}")
        return
    print(f"{config_path}: signing.key {old_key} -> {new_key}")


def migrated_text(old_text: str, old_key: str, new_key: str) -> str:
    """Replace the first ``key = "<old_key>"`` line with one naming ``new_key``.

    The result is unverified; the caller compares its parsed settings with the
    expected ones, which also rejects a match outside ``[signing]``.
    """
    key_line = re.compile(
        r'^(?P<lead>[ \t]*(?:signing[ \t]*\.[ \t]*)?key[ \t]*=[ \t]*)"' + re.escape(old_key) + '"',
        re.MULTILINE,
    )
    return key_line.sub(lambda match: f'{match["lead"]}"{new_key}"', old_text, count=1)


def write_atomic(path: Path, content: str) -> None:
    """Replace ``path`` with ``content`` atomically, keeping its file mode."""
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
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
    print(f"migrate-jj-signing-key: {config_path}: {message}", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
