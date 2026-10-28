"""Policy documents shaped like the jj and git policies, for tests."""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import TypeAlias

Json: TypeAlias = "str | bool | list[Json] | dict[str, Json]"
JsonObject: TypeAlias = "dict[str, Json]"

def jj_ignore_immutable_rule(overrides: JsonObject | None = None) -> JsonObject:
    """Return the jj.ignore-immutable refuse-option rule with OVERRIDES applied."""
    return {
        **_JJ_IGNORE_IMMUTABLE_RULE,
        **({} if overrides is None else overrides),
    }


def jj_git_push_rule(overrides: JsonObject | None = None) -> JsonObject:
    """Return the jj.git-push allowlist rule with OVERRIDES applied."""
    return {
        **_JJ_GIT_PUSH_RULE,
        **({} if overrides is None else overrides),
    }


_JJ_IGNORE_IMMUTABLE_RULE: JsonObject = {
    "id": "jj.ignore-immutable",
    "kind": "refuse-option",
    "scope": "any",
    "refused-options": ["--ignore-immutable"],
    "message": "It lifts the protection of trunk.",
}

_JJ_GIT_PUSH_RULE: JsonObject = {
    "id": "jj.git-push",
    "kind": "allowlist",
    "scope": ["git", "push"],
    "message": "Push named bookmarks with `-b <name>`.",
    "allowed-options": [
        {"names": ["-b", "--bookmark"], "arity": "value", "value-constraint": "literal-name"},
        {"names": ["-c", "--change"], "arity": "value"},
        {"names": ["--named"], "arity": "value", "value-constraint": "literal-name-before-equals"},
        {"names": ["--remote"], "arity": "value", "value-constraint": "literal-name"},
        {"names": ["--dry-run"], "arity": "flag"},
    ],
    "allowed-global-options": ["-R", "--quiet", "--color", "-h"],
    "target-options": ["-b", "-c", "--named"],
    "informational-options": ["-h"],
}


def jj_tool(executable: str = "/bin/jj", rules: list[Json] | None = None) -> JsonObject:
    """Return a jj-like tool: globals anywhere, the two jj rules by default."""
    return {
        "executable": executable,
        "prefix-arguments": ["--config", "ui.editor=denied"],
        "global-options-position": "anywhere",
        "global-options": [
            {"names": ["-R", "--repository"], "arity": "value"},
            {"names": ["--ignore-immutable"], "arity": "flag"},
            {"names": ["--at-operation", "--at-op"], "arity": "value"},
            {"names": ["--quiet"], "arity": "flag"},
            {"names": ["--color"], "arity": "value"},
            {"names": ["--config"], "arity": "value"},
            {"names": ["-h", "--help"], "arity": "flag"},
        ],
        "rules": [jj_ignore_immutable_rule(), jj_git_push_rule()] if rules is None else rules,
    }


def git_tool(executable: str = "/bin/git") -> JsonObject:
    """Return a git-like tool: globals before the subcommand, `git push` refused."""
    return {
        "executable": executable,
        "prefix-arguments": [],
        "global-options-position": "before-subcommand",
        "global-options": [
            {"names": ["-C"], "arity": "value"},
            {"names": ["-c"], "arity": "value"},
            {"names": ["--git-dir"], "arity": "value"},
            {"names": ["--no-pager", "-P"], "arity": "flag"},
            {"names": ["--exec-path"], "arity": "optional-value"},
        ],
        "rules": [
            {
                "id": "git.push",
                "kind": "refuse-subcommand",
                "scope": ["push"],
                "message": "Publish with `jj git push`.",
            }
        ],
    }


def policy_document(jj: JsonObject | None = None, git: JsonObject | None = None) -> JsonObject:
    """Return a policy document with a jj and a git tool, defaulting each."""
    return copy.deepcopy(
        {
            "tools": {
                "jj": jj_tool() if jj is None else jj,
                "git": git_tool() if git is None else git,
            }
        }
    )


def write_policy(directory: Path, document: JsonObject) -> Path:
    """Write DOCUMENT as policy JSON in DIRECTORY and return its path."""
    path = directory / "policy.json"
    _ = path.write_text(json.dumps(document), encoding="utf-8")
    return path
