"""Run external commands with consistent launch and failure diagnostics."""

from __future__ import annotations

import os
import shlex
import subprocess
from collections.abc import Sequence
from pathlib import Path
from typing import TypeVar


CommandError = TypeVar("CommandError", bound=Exception)


def capture_bytes(
    command: Sequence[str],
    *,
    error_type: type[CommandError],
    cwd: Path | None = None,
    stdin: bytes | None = None,
) -> subprocess.CompletedProcess[bytes]:
    """Run COMMAND and capture byte streams, translating process launch failures."""
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            input=stdin,
            check=False,
            capture_output=True,
        )
    except OSError as error:
        raise error_type(f"could not run {command[0]}: {error}") from error


def checked_bytes(
    command: Sequence[str],
    *,
    error_type: type[CommandError],
    cwd: Path | None = None,
    stdin: bytes | None = None,
) -> bytes:
    """Return COMMAND's stdout, raising ERROR_TYPE with captured diagnostics on failure."""
    result = capture_bytes(command, error_type=error_type, cwd=cwd, stdin=stdin)
    if result.returncode != 0:
        detail = os.fsdecode(result.stderr).strip()
        suffix = f": {detail}" if detail else ""
        raise error_type(f"{shlex.join(command)} failed{suffix}")
    return result.stdout


def capture_text(
    command: Sequence[str],
    *,
    error_type: type[CommandError],
    stdin: str | None = None,
    capture_stderr: bool = False,
) -> subprocess.CompletedProcess[str]:
    """Run COMMAND with captured text stdout and optional captured stderr."""
    try:
        return subprocess.run(
            command,
            input=stdin,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE if capture_stderr else None,
            text=True,
        )
    except OSError as error:
        raise error_type(f"could not run {command[0]}: {error}") from error


def run_status(
    command: Sequence[str],
    *,
    error_type: type[CommandError],
    cwd: Path | None = None,
) -> int:
    """Run COMMAND with inherited streams and return its status."""
    try:
        return subprocess.run(command, cwd=cwd, check=False).returncode
    except OSError as error:
        raise error_type(f"could not run {command[0]}: {error}") from error
