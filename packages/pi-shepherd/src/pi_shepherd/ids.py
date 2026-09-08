"""Immutable names and injective identity markers, independent of runtime routing."""

import os
import re
import secrets
from pathlib import Path

from .errors import require

ALPHABET = "0123456789abcdefghjkmnpqrstvwxyz"
NAME = re.compile(r"[a-z][a-z0-9_-]{0,63}\Z")


def new_id(prefix: str) -> str:
    return prefix + "".join(secrets.choice(ALPHABET) for _ in range(26))


def is_id(value: str, prefix: str = "tm_") -> bool:
    return (
        value.startswith(prefix)
        and len(value) == len(prefix) + 26
        and all(char in ALPHABET for char in value[len(prefix) :])
    )


def logical_name(value: str) -> str:
    require(
        bool(NAME.fullmatch(value)) and not value.startswith("tm_"),
        "invalid_name",
        "Use an ASCII name starting with a letter, not tm_, up to 64 characters",
    )
    return value


def alias(teammate_id: str) -> str:
    require(is_id(teammate_id), "invalid_id", "Invalid teammate ID")
    return "ps_" + teammate_id[3:]


def marker(teammate_id: str) -> str:
    require(is_id(teammate_id), "invalid_id", "Invalid teammate ID")
    return "pi-shepherd:" + teammate_id


def tab_label(teammate_id: str, name: str) -> str:
    """Put the immutable task name first while retaining the full identity marker."""
    return f"{logical_name(name)} [{marker(teammate_id)}]"


def resolve_cwd(requested: str | None, pwd: str) -> str:
    require(
        os.path.isabs(pwd) and "\0" not in pwd, "invalid_cwd", "PWD must be absolute"
    )
    value = pwd if requested is None else requested
    require(bool(value) and "\0" not in value, "invalid_cwd", "Invalid cwd")
    if not os.path.isabs(value):
        value = os.path.normpath(os.path.join(pwd, value))
    require(Path(value).is_dir(), "invalid_cwd", "cwd must be an existing directory")
    return value
