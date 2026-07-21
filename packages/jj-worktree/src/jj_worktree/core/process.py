from __future__ import annotations

import os
import subprocess
from collections.abc import Sequence
from pathlib import Path


class WorktreeError(Exception):
    """Report a user-facing lifecycle or repository validation failure."""


def run(
    command: Sequence[str],
    *,
    cwd: Path | None = None,
    input_data: bytes | None = None,
) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            input=input_data,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise WorktreeError(f"could not run {command[0]}: {error}") from error


def checked(
    command: Sequence[str], *, cwd: Path | None = None, label: str | None = None
) -> bytes:
    result = run(command, cwd=cwd)
    if result.returncode != 0:
        detail = os.fsdecode(result.stderr).strip()
        suffix = f": {detail}" if detail else ""
        operation = label if label is not None else " ".join(command)
        raise WorktreeError(f"{operation} failed{suffix}")
    return result.stdout


def single_line(output: bytes, operation: str) -> str:
    if not output.endswith(b"\n") or b"\n" in output[:-1] or not output[:-1]:
        raise WorktreeError(f"{operation} returned invalid output")
    return os.fsdecode(output[:-1])
