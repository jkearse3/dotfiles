from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final
from unittest.mock import patch

from agent_policy.checks import NAMED_CHECKS, CheckRefusal, CheckRequest
from agent_policy.policy import (
    AllowlistRule,
    PolicyError,
    RefuseOptionRule,
    load_policy,
    parse_policy,
)

from policy_fixtures import (
    Json,
    JsonObject,
    jj_git_push_rule,
    jj_ignore_immutable_rule,
    jj_tool,
    policy_document,
)

def _jj_policy(*rules: Json, executable: str = "/bin/jj") -> JsonObject:
    """Return a policy whose jj tool has exactly RULES."""
    return policy_document(jj=jj_tool(executable, rules=list(rules)))


def _problems(test: unittest.TestCase, document: JsonObject) -> str:
    with test.assertRaises(PolicyError) as caught:
        _ = parse_policy(document)
    return "\n".join(caught.exception.problems)


def _passing_check(_request: CheckRequest) -> CheckRefusal | None:
    return None


@final
class PolicyValidationTests(unittest.TestCase):
    """An invalid policy fails validation with a message locating the problem."""

    def test_valid_policy_parses_into_typed_rules(self) -> None:
        policy = parse_policy(policy_document())
        ignore_immutable, git_push = policy.tools["jj"].rules
        self.assertIsInstance(ignore_immutable, RefuseOptionRule)
        assert isinstance(git_push, AllowlistRule)
        self.assertEqual({"-b", "-c", "--named"}, {d.names[0] for d in git_push.target_options})

    def test_problems_are_reported(self) -> None:
        ignore_immutable = jj_ignore_immutable_rule()
        cases: list[tuple[str, JsonObject, str]] = [
            (
                "duplicate ID",
                _jj_policy(ignore_immutable, jj_git_push_rule({"id": "jj.ignore-immutable"})),
                "duplicate rule ID 'jj.ignore-immutable'",
            ),
            (
                "unknown kind",
                _jj_policy(jj_ignore_immutable_rule({"kind": "refuse-everything"})),
                "unknown kind 'refuse-everything'",
            ),
            (
                "unknown check",
                _jj_policy(jj_git_push_rule({"checks": ["no-such-check"]})),
                "unknown check 'no-such-check'",
            ),
            (
                "ID of another tool",
                _jj_policy(jj_ignore_immutable_rule({"id": "git.ignore-immutable"})),
                "must be jj.<rule>",
            ),
            (
                "unknown arity",
                _jj_policy(jj_git_push_rule({"allowed-options": [{"names": ["--x"], "arity": "maybe"}]})),
                "unknown value 'maybe'",
            ),
            (
                "short optional value",
                _jj_policy(
                    jj_git_push_rule({"allowed-options": [{"names": ["-x"], "arity": "optional-value"}]})
                ),
                "optional-value options must have only long names",
            ),
            (
                "unknown constraint",
                _jj_policy(
                    jj_git_push_rule(
                        {"allowed-options": [{"names": ["--x"], "arity": "value", "value-constraint": "short"}]}
                    )
                ),
                "unknown value 'short'",
            ),
            (
                "key of another kind",
                _jj_policy(jj_ignore_immutable_rule({"allowed-options": []})),
                "unknown keys ['allowed-options']",
            ),
            (
                "malformed option name",
                _jj_policy(jj_ignore_immutable_rule({"refused-options": ["ignore-immutable"]})),
                "malformed option names",
            ),
            (
                "undeclared global",
                _jj_policy(jj_git_push_rule({"allowed-global-options": ["--no-such-global"]})),
                "--no-such-global is not a declared global option",
            ),
            (
                "global in allowed options",
                _jj_policy(jj_git_push_rule({"allowed-options": [{"names": ["--quiet"], "arity": "flag"}]})),
                "--quiet is a global option",
            ),
            (
                "refuse-subcommand without path",
                _jj_policy({"id": "jj.everything", "kind": "refuse-subcommand", "scope": "any", "message": "No."}),
                "refuse-subcommand needs a subcommand path",
            ),
            (
                "relative executable",
                _jj_policy(executable="jj"),
                "must be an absolute path",
            ),
        ]
        for name, document, expected in cases:
            with self.subTest(name):
                self.assertIn(expected, _problems(self, document))

    def test_registered_check_is_accepted(self) -> None:
        document = _jj_policy(jj_git_push_rule({"checks": ["known-check"]}))
        with patch.dict(NAMED_CHECKS, {"known-check": _passing_check}):
            _ = parse_policy(document)

    def test_every_problem_is_reported_at_once(self) -> None:
        problems = _problems(
            self,
            _jj_policy(
                jj_ignore_immutable_rule({"kind": "nope"}),
                jj_git_push_rule({"checks": ["missing"]}),
            ),
        )
        self.assertIn("unknown kind", problems)
        self.assertIn("unknown check", problems)

    def test_unreadable_or_non_json_file(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / "policy.json"
            _ = path.write_text("{", encoding="utf-8")
            with self.assertRaisesRegex(PolicyError, "cannot read policy"):
                _ = load_policy(path)
            with self.assertRaisesRegex(PolicyError, "cannot read policy"):
                _ = load_policy(Path(directory) / "missing.json")
