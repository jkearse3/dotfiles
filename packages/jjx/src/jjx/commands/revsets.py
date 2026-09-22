"""Construct Jujutsu revsets and string patterns from literal names."""

from __future__ import annotations

import json
from typing import TypeVar, cast

CommandError = TypeVar("CommandError", bound=Exception)


def decode_json_string(
    serialized: str,
    *,
    error_type: type[CommandError],
    context: str,
) -> str:
    """Decode one JSON string emitted by a machine-readable jj template."""
    try:
        value = cast(object, json.loads(serialized))
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        raise error_type(f"jj returned an invalid {context}") from error
    if not isinstance(value, str):
        raise error_type(f"jj returned an invalid {context}")
    return value

def exact_string_pattern(value: str) -> str:
    """Return a jj string pattern that matches VALUE literally and exactly."""
    return f"exact:{json.dumps(value, ensure_ascii=False)}"


def bookmark_revset(name: str) -> str:
    """Return a revset selecting the local bookmark named NAME exactly."""
    return f"bookmarks({exact_string_pattern(name)})"
