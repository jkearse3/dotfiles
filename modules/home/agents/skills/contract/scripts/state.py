#!/usr/bin/env python3
"""Maintain branch-contract reconciliation sidecar state."""

from __future__ import annotations

import hashlib
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import TextIO, TypedDict, cast


FRESH = 0
STALE = 1
ERROR = 2

STATE_FIELDS = (
    "contract_sha256",
    "working_copy_commit_id",
)


class ExpectedState(TypedDict):
    contract_sha256: str
    working_copy_commit_id: str


class CollectedState(TypedDict):
    root: Path
    contract_path: Path
    state_path: Path
    state: ExpectedState

USAGE = """usage:
  state.py paths
  state.py check
  state.py write
  state.py --help

Maintains reconciliation cache state for the current bookmark's branch contract.

Run from the target jj worktree. The helper derives both local-state paths from
the jj root and current bookmark:

  <jj-root>/.agent/contracts/<bookmark-slug>.md
  <jj-root>/.agent/contracts/<bookmark-slug>.state.json

Modes:
  paths  Print the resolved jj root, current bookmark, bookmark slug, Markdown
         contract path, and sidecar state path. Exits 0 when resolved and 2 for
         diagnostics. Does not require an existing contract and does not write.
  check  Compare the derived state file with the current contract hash, current
         jj working-copy commit_id, and the two-field sidecar schema. Exits 0
         for fresh state, 1 for safely stale state, and 2 for diagnostics that
         require stopping.
  write  Write the derived state file from the final contract and current jj
         working-copy revision after approval. Exits 0 when written and 2 for
         diagnostics.

The helper takes no path arguments. Extra arguments are rejected. In write mode,
/.agent/contracts/ and the derived Markdown and JSON paths must already be
ignored locally.
"""


class Diagnostic(Exception):
    """A stop-worthy diagnostic with a stable reason string."""

    reason: str
    detail: object | None

    def __init__(self, reason: str, detail: object | None = None) -> None:
        super().__init__(reason)
        self.reason = reason
        self.detail = detail


def field(name: str, value: object) -> str:
    return f"{name}={shlex.quote(str(value))}"


def print_status(**items: object) -> None:
    print(" ".join(field(name, value) for name, value in items.items()))


def fail(reason: str, detail: object | None = None) -> int:
    if detail is None:
        print(f"error: {reason}", file=sys.stderr)
    else:
        print(f"error: {reason} {field('detail', detail)}", file=sys.stderr)
    return ERROR


def run(cmd: list[str], cwd: Path, reason: str) -> str:
    try:
        completed = subprocess.run(
            cmd,
            cwd=str(cwd),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except FileNotFoundError:
        raise Diagnostic(reason, f"{cmd[0]} unavailable")

    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or f"exit {completed.returncode}"
        raise Diagnostic(reason, detail)

    return completed.stdout.rstrip("\n")


def one_nonempty_line(output: str, reason: str) -> str:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if len(lines) != 1:
        raise Diagnostic(reason, f"expected 1 line, got {len(lines)}")
    return lines[0]


def jj_root() -> Path:
    output = run(["jj", "root"], Path.cwd(), "jj-root-failed")
    return Path(one_nonempty_line(output, "jj-root-failed")).resolve()


def current_bookmark(root: Path) -> str:
    output = run(["jj-bookmark-current"], root, "current-bookmark-unresolved")
    lines = [line.strip() for line in output.splitlines() if line.strip()]

    if not lines:
        raise Diagnostic("current-bookmark-unresolved", "jj-bookmark-current returned no bookmark")
    if len(lines) > 1:
        raise Diagnostic("multiple-current-bookmarks", ",".join(lines))

    return lines[0]


def bookmark_slug(bookmark: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", bookmark)
    slug = re.sub(r"-+", "-", slug).strip("-")
    if not slug:
        raise Diagnostic("bookmark-slug-empty", bookmark)
    return slug


def contract_paths(root: Path, bookmark: str) -> tuple[Path, Path]:
    slug = bookmark_slug(bookmark)
    contract_path = root / ".agent" / "contracts" / f"{slug}.md"
    return contract_path, contract_path.with_suffix(".state.json")


def read_contract_bookmark(contract_path: Path) -> str:
    try:
        text = contract_path.read_text(encoding="utf-8")
    except OSError as err:
        raise Diagnostic("contract-unreadable", err)
    except UnicodeDecodeError as err:
        raise Diagnostic("contract-not-utf8", err)

    bookmarks: list[str] = []
    for line in text.splitlines():
        if line.startswith("## "):
            break
        if line.startswith("Bookmark:"):
            bookmarks.append(line[len("Bookmark:") :].strip())

    if len(bookmarks) != 1 or not bookmarks[0]:
        raise Diagnostic("contract-bookmark-ambiguous", f"found {len(bookmarks)} Bookmark lines")

    return bookmarks[0]


def contract_sha256(contract_path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with contract_path.open("rb") as contract_file:
            for chunk in iter(lambda: contract_file.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as err:
        raise Diagnostic("contract-unreadable", err)
    return digest.hexdigest()


def ensure_contract_file(contract_path: Path) -> None:
    if not contract_path.exists():
        raise Diagnostic("contract-path-missing", contract_path)
    if not contract_path.is_file():
        raise Diagnostic("contract-path-not-file", contract_path)


def working_copy_commit_id(root: Path) -> str:
    output = run(
        ["jj", "-R", str(root), "log", "-r", "@", "--no-graph", "-T", 'commit_id ++ "\\n"'],
        root,
        "working-copy-commit-unresolved",
    )
    return one_nonempty_line(output, "working-copy-commit-unresolved")


def collect_state() -> CollectedState:
    root = jj_root()
    bookmark = current_bookmark(root)
    contract_path, state_path = contract_paths(root, bookmark)
    ensure_contract_file(contract_path)

    contract_bookmark = read_contract_bookmark(contract_path)
    if contract_bookmark != bookmark:
        raise Diagnostic(
            "contract-bookmark-mismatch",
            f"contract={contract_bookmark} current={bookmark}",
        )

    return {
        "root": root,
        "contract_path": contract_path,
        "state_path": state_path,
        "state": {
            "contract_sha256": contract_sha256(contract_path),
            "working_copy_commit_id": working_copy_commit_id(root),
        },
    }


def paths() -> int:
    root = jj_root()
    bookmark = current_bookmark(root)
    slug = bookmark_slug(bookmark)
    contract_path, state_path = contract_paths(root, bookmark)

    print_status(
        root=root,
        bookmark=bookmark,
        bookmark_slug=slug,
        contract_path=contract_path,
        state_path=state_path,
    )
    return FRESH


def load_state(state_path: Path) -> object | None:
    if not state_path.exists():
        return None

    try:
        with state_path.open("r", encoding="utf-8") as state_file:
            return cast(object, json.load(state_file))
    except json.JSONDecodeError as err:
        raise Diagnostic("state-json-malformed", err)
    except OSError as err:
        raise Diagnostic("state-unreadable", err)


def string_key_dict(value: object) -> dict[str, object] | None:
    if not isinstance(value, dict):
        return None

    raw = cast(dict[object, object], value)
    result: dict[str, object] = {}
    for key, item in raw.items():
        if not isinstance(key, str):
            return None
        result[key] = item
    return result


def stale_reasons(actual: object | None, expected: ExpectedState) -> list[str]:
    if actual is None:
        return ["missing-state"]

    actual_state = string_key_dict(actual)
    if actual_state is None:
        return ["schema-mismatch"]

    reasons: list[str] = []
    actual_fields = set(actual_state)
    expected_fields = set(STATE_FIELDS)
    if actual_fields != expected_fields:
        reasons.append("schema-mismatch")

    for key, expected_value in expected.items():
        if actual_state.get(key) != expected_value:
            reasons.append(key)

    return reasons


def check() -> int:
    collected = collect_state()
    actual = load_state(collected["state_path"])
    reasons = stale_reasons(actual, collected["state"])

    if reasons:
        print_status(status="stale", reason=",".join(dict.fromkeys(reasons)))
        return STALE

    print_status(status="fresh")
    return FRESH


def relative_to_root(path: Path, root: Path, reason: str) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        raise Diagnostic(reason, path)


def ensure_ignored(root: Path, path: Path, outside_reason: str, not_ignored_reason: str) -> None:
    relative_path = relative_to_root(path, root, outside_reason)
    if path.is_dir() and not relative_path.endswith("/"):
        relative_path = f"{relative_path}/"

    try:
        completed = subprocess.run(
            ["git", "-C", str(root), "check-ignore", "-q", "--", relative_path],
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        raise Diagnostic("git-unavailable", "cannot verify local ignore rule")

    if completed.returncode != 0:
        detail = completed.stderr.strip() or relative_path
        raise Diagnostic(not_ignored_reason, detail)


def write() -> int:
    collected = collect_state()
    root = collected["root"]
    contract_path = collected["contract_path"]
    state_path = collected["state_path"]

    ensure_ignored(
        root,
        root / ".agent" / "contracts",
        "contracts-dir-outside-jj-root",
        "contracts-dir-not-ignored",
    )
    ensure_ignored(root, contract_path, "contract-outside-jj-root", "contract-path-not-ignored")
    ensure_ignored(root, state_path, "state-outside-jj-root", "state-path-not-ignored")

    try:
        with state_path.open("w", encoding="utf-8") as state_file:
            json.dump(collected["state"], state_file, indent=2)
            _ = state_file.write("\n")
    except OSError as err:
        raise Diagnostic("state-write-failed", err)

    print_status(status="written")
    return FRESH


def usage(stream: TextIO = sys.stderr) -> int:
    print(USAGE.rstrip(), file=stream)
    return ERROR


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] in {"-h", "--help", "help"}:
        _ = usage(sys.stdout)
        return FRESH
    if len(argv) != 2:
        return usage()

    mode = argv[1]
    try:
        if mode == "paths":
            return paths()
        if mode == "check":
            return check()
        if mode == "write":
            return write()
    except Diagnostic as err:
        return fail(err.reason, err.detail)

    return usage()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
