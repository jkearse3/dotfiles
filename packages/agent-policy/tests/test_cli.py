from __future__ import annotations

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import cast, final, override

from policy_fixtures import git_tool, jj_git_push_rule, jj_ignore_immutable_rule, jj_tool, policy_document, write_policy

# The installed entry point when the package build provides it, otherwise the
# module from the source tree.
CLI = [os.environ["AGENT_POLICY"]] if "AGENT_POLICY" in os.environ else [sys.executable, "-m", "agent_policy"]

FAKE_TOOL = """\
import json, os, sys
with open(os.environ["FAKE_TOOL_RECORD"], "w") as record:
    json.dump({"argv": sys.argv, "approve": os.environ.get("AGENT_POLICY_APPROVE")}, record)
"""


@final
class RunTests(unittest.TestCase):
    """`agent-policy run` execs the real binary or refuses with a corrective message."""

    @override
    def setUp(self) -> None:
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.record = self.directory / "record.json"

        self.fake_tool = self.directory / "fake-tool"
        _ = self.fake_tool.write_text(f"#!{sys.executable}\n{FAKE_TOOL}", encoding="utf-8")
        self.fake_tool.chmod(0o755)
        document = policy_document(jj=jj_tool(str(self.fake_tool)), git=git_tool(str(self.fake_tool)))
        self.policy = write_policy(self.directory, document)

    def run_cli(
        self, *arguments: str, approve: str | None = None, policy: Path | None = None
    ) -> subprocess.CompletedProcess[str]:
        environment = {**os.environ, "FAKE_TOOL_RECORD": str(self.record)}
        _ = environment.pop("AGENT_POLICY_APPROVE", None)
        if approve is not None:
            environment["AGENT_POLICY_APPROVE"] = approve
        return subprocess.run(
            [*CLI, "run", "--policy", str(self.policy if policy is None else policy), *arguments],
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def recorded(self) -> object:
        """Return what the fake tool recorded, or ``None`` when it did not run."""
        if not self.record.exists():
            return None
        return cast(object, json.loads(self.record.read_text(encoding="utf-8")))

    def test_allowed_command_execs_real_binary_with_prefix_and_without_approval(self) -> None:
        result = self.run_cli("jj", "--", "git", "push", "-b", "main", approve="jj.git-push")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            {
                "argv": [str(self.fake_tool), "--config", "ui.editor=denied", "git", "push", "-b", "main"],
                "approve": None,
            },
            self.recorded(),
        )

    def test_governed_argv_may_contain_double_dash_and_agent_policy_options(self) -> None:
        result = self.run_cli("jj", "--", "file", "show", "--policy", "x", "--", "--ignore-immutable")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            {
                "argv": [
                    str(self.fake_tool),
                    "--config",
                    "ui.editor=denied",
                    *("file", "show", "--policy", "x", "--", "--ignore-immutable"),
                ],
                "approve": None,
            },
            self.recorded(),
        )

    def test_refusal_message_and_exit(self) -> None:
        result = self.run_cli("jj", "--", "git", "push", "-b", "x", "--all")
        self.assertEqual(1, result.returncode)
        self.assertIsNone(self.recorded())
        self.assertTrue(result.stderr.startswith("jj (agent policy): jj.git-push refused this command: "))
        self.assertIn("`--all` is not an allowed option for `jj git push`.", result.stderr)
        self.assertIn("Push named bookmarks with `-b <name>`.", result.stderr)
        self.assertIn("rerun this same single command prefixed with `AGENT_POLICY_APPROVE=jj.git-push`", result.stderr)
        self.assertIn("never export", result.stderr)

    def test_several_refusals_each_get_a_line_and_a_combined_approval(self) -> None:
        result = self.run_cli("jj", "--", "git", "push", "--all", "--ignore-immutable")
        lines = result.stderr.splitlines()
        self.assertEqual(3, len(lines))
        self.assertTrue(all(line.startswith("jj (agent policy): ") for line in lines))
        self.assertIn("AGENT_POLICY_APPROVE=jj.ignore-immutable,jj.git-push", lines[2])

    def test_approval_matrix(self) -> None:
        for approve, expected_status in (
            ("git.push", 0),
            (None, 1),
            ("", 1),
            ("1", 1),
            ("jj.ignore-immutable", 1),
        ):
            with self.subTest(approve=approve):
                self.record.unlink(missing_ok=True)
                result = self.run_cli("git", "--", "-C", "repo", "push", approve=approve)
                self.assertEqual(expected_status, result.returncode, result.stderr)
                self.assertEqual(expected_status == 0, self.recorded() is not None)
                if expected_status != 0:
                    self.assertIn("git (agent policy): git.push refused this command", result.stderr)

    def test_runtime_failures_refuse_without_exec(self) -> None:
        malformed = self.directory / "malformed.json"
        _ = malformed.write_text('{"tools": {"jj": {}}}', encoding="utf-8")
        for arguments, policy, expected in (
            (("jj", "--", "log"), malformed, "cannot load policy"),
            (("jj", "--", "log"), self.directory / "missing.json", "cannot load policy"),
            (("hg", "--", "log"), None, "'hg' is not a tool in policy"),
        ):
            with self.subTest(expected=expected, policy=policy):
                result = self.run_cli(*arguments, policy=policy)
                self.assertEqual(2, result.returncode)
                self.assertIn(expected, result.stderr)
                self.assertIn("refusing to run", result.stderr)
                self.assertIsNone(self.recorded())

    def test_run_requires_double_dash(self) -> None:
        result = self.run_cli("jj", "log")
        self.assertEqual(2, result.returncode)
        self.assertIsNone(self.recorded())


@final
class ValidateTests(unittest.TestCase):
    """`agent-policy validate` reports problems through its exit status."""

    def test_valid_and_invalid_policies(self) -> None:
        with TemporaryDirectory() as directory:
            valid = write_policy(Path(directory), policy_document())
            result = subprocess.run([*CLI, "validate", str(valid)], capture_output=True, text=True, check=False)
            self.assertEqual((0, ""), (result.returncode, result.stderr))

            duplicate = jj_git_push_rule({"id": "jj.ignore-immutable"})
            document = policy_document(jj=jj_tool(rules=[jj_ignore_immutable_rule(), duplicate]))
            invalid = write_policy(Path(directory), document)
            result = subprocess.run([*CLI, "validate", str(invalid)], capture_output=True, text=True, check=False)
            self.assertEqual(1, result.returncode)
            self.assertIn(f"agent-policy: {invalid}: ", result.stderr)
            self.assertIn("duplicate rule ID 'jj.ignore-immutable'", result.stderr)
