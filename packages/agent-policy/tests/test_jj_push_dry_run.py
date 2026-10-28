from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import cast, final, override

from agent_policy.evaluation import evaluate
from agent_policy.invocation import parse_invocation
from agent_policy.jj_push_dry_run import (
    BookmarkAction,
    dry_run_argv,
    dry_run_report_problem,
    read_dry_run_report,
)
from agent_policy.policy import AllowlistRule, Tool, parse_policy

from policy_fixtures import jj_git_push_rule, jj_tool, policy_document

COMMAND = "jj git push -b a --dry-run --color=never"

ADD = """\
Changes to push to origin:
  bookmark: a [add to 229150406da2]
Dry-run requested, not pushing.
"""

FORWARD = """\
Changes to push to origin:
  bookmark: a [move forward from 229150406da2 to 9ef174a73888]
Dry-run requested, not pushing.
"""

SIDEWAYS = """\
Changes to push to origin:
  bookmark: a [move sideways from 229150406da2 to 5c978ed93fce]
Dry-run requested, not pushing.
"""

BACKWARD = """\
Changes to push to origin:
  bookmark: a [move backward from ea8c05c34678 to 492ad150763d]
Dry-run requested, not pushing.
"""

DELETE = """\
Changes to push to origin:
  bookmark: a [delete from 229150406da2]
Dry-run requested, not pushing.
"""

CHANGE_ALL = """\
Creating bookmark push-zvzvnnqmoppw for revision zvzvnnqmoppw
Creating bookmark push-qpkpuxsvxmlt for revision qpkpuxsvxmlt
Changes to push to origin:
  bookmark: push-zvzvnnqmoppw [add to 5c978ed93fce]
  bookmark: push-qpkpuxsvxmlt [add to 9ef174a73888]
Dry-run requested, not pushing.
"""

ALREADY_MATCHES = """\
Bookmark a@origin already matches a
Nothing changed.
"""

NO_MATCHING_BOOKMARK = """\
Warning: No matching bookmarks for names: nope
Nothing changed.
"""


def problem(output: str, target_count: int = 1) -> str | None:
    return dry_run_report_problem(read_dry_run_report(output), target_count, COMMAND)


@final
class DryRunReportTests(unittest.TestCase):
    """Reading jj's dry-run report and judging the push it describes."""

    def test_actions_are_read(self) -> None:
        cases = {
            ADD: BookmarkAction.ADD,
            FORWARD: BookmarkAction.MOVE_FORWARD,
            SIDEWAYS: BookmarkAction.MOVE_SIDEWAYS,
            BACKWARD: BookmarkAction.MOVE_BACKWARD,
            DELETE: BookmarkAction.DELETE,
        }
        for output, action in cases.items():
            with self.subTest(action=action):
                report = read_dry_run_report(output)
                self.assertEqual([("a", action)], [(change.name, change.action) for change in report.bookmark_changes])
                self.assertEqual((), report.unrecognized_lines)

    def test_additions_forward_moves_and_no_changes_pass(self) -> None:
        for output in (ADD, FORWARD, ALREADY_MATCHES, "Nothing changed.\n", f"{ADD}Hint: something\n"):
            with self.subTest(output=output):
                self.assertIsNone(problem(output))

    def test_sideways_backward_and_delete_refuse_as_force_pushes(self) -> None:
        for output, description in (
            (SIDEWAYS, "move sideways from 229150406da2 to 5c978ed93fce"),
            (BACKWARD, "move backward from ea8c05c34678 to 492ad150763d"),
            (DELETE, "delete from 229150406da2"),
        ):
            with self.subTest(description=description):
                reason = problem(output)
                assert reason is not None
                self.assertIn(f"`a` ({description})", reason)
                self.assertIn("is a force push", reason)

    def test_more_changes_than_targets_refuse(self) -> None:
        self.assertIsNone(problem(CHANGE_ALL, target_count=2))
        reason = problem(CHANGE_ALL, target_count=1)
        assert reason is not None
        self.assertIn("changes 2 bookmarks but the command names only 1 target;", reason)

    def test_unrecognized_lines_refuse(self) -> None:
        for output, line in (
            (NO_MATCHING_BOOKMARK, "Warning: No matching bookmarks for names: nope"),
            (f"{ADD}  tag: v1 [add to 229150406da2]\n", "  tag: v1 [add to 229150406da2]"),
            (ADD.replace("add to", "replace with"), "  bookmark: a [replace with 229150406da2]"),
            (f"\x1b[1m{ADD}", "\x1b[1mChanges to push to origin:"),
        ):
            with self.subTest(line=line):
                reason = problem(output)
                assert reason is not None
                self.assertIn(f"does not recognize: `{line}`", reason)

    def test_report_without_header_or_nothing_changed_refuses(self) -> None:
        for output in ("", "Dry-run requested, not pushing.\n"):
            with self.subTest(output=output):
                reason = problem(output)
                assert reason is not None
                self.assertIn("neither `Changes to push to <remote>:` nor `Nothing changed.`", reason)


def _jj_tool(executable: str) -> Tool:
    rule = jj_git_push_rule({"checks": ["jj-push-dry-run"]})
    return parse_policy(policy_document(jj=jj_tool(executable, rules=[rule]))).tools["jj"]


@final
class DryRunArgvTests(unittest.TestCase):
    """The dry run reruns the agent's argv without report-altering globals."""

    def dry_run(self, argv: list[str]) -> list[str]:
        tool = _jj_tool("/bin/jj")
        rule = tool.rules[0]
        assert isinstance(rule, AllowlistRule)
        return dry_run_argv(parse_invocation(tool, argv, rule.allowed_options))

    def test_report_altering_globals_are_dropped_anywhere(self) -> None:
        self.assertEqual(
            ["-R", "repo", "git", "push", "-b", "x", "--dry-run", "--color=never"],
            self.dry_run(
                ["--quiet", "-R", "repo", "git", "--color", "always", "push", "--debug", "-b", "x", "--color=auto"]
            ),
        )

    def test_dry_run_options_go_before_double_dash(self) -> None:
        self.assertEqual(
            ["git", "push", "-c", "@", "--dry-run", "--color=never", "--", "--quiet"],
            self.dry_run(["git", "push", "-c", "@", "--", "--quiet"]),
        )


FAKE_JJ = """\
import json, os, sys
with open(os.environ["FAKE_JJ_RECORD"], "w") as record:
    json.dump({"argv": sys.argv, "approve": os.environ.get("AGENT_POLICY_APPROVE")}, record)
sys.stderr.write(os.environ["FAKE_JJ_OUTPUT"])
sys.exit(int(os.environ["FAKE_JJ_EXIT"]))
"""


@final
class DryRunCheckTests(unittest.TestCase):
    """The check runs the real tool's dry run and refuses under jj.git-push."""

    @override
    def setUp(self) -> None:
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.record = Path(directory.name) / "record.json"
        self.fake_jj = Path(directory.name) / "jj"
        _ = self.fake_jj.write_text(f"#!{sys.executable}\n{FAKE_JJ}", encoding="utf-8")
        self.fake_jj.chmod(0o755)
        self.tool = _jj_tool(str(self.fake_jj))

    def refusal_reasons(self, argv: list[str], output: str, exit_status: int = 0, approve: str = "") -> list[str]:
        environment = {
            "FAKE_JJ_RECORD": str(self.record),
            "FAKE_JJ_OUTPUT": output,
            "FAKE_JJ_EXIT": str(exit_status),
            "AGENT_POLICY_APPROVE": approve,
        }
        refusals = evaluate(self.tool, argv, environment)
        self.assertEqual(["jj.git-push"] * len(refusals), [refusal.rule.id for refusal in refusals])
        return [reason for refusal in refusals for reason in refusal.reasons]

    def recorded(self) -> object:
        """Return what the fake jj recorded, or ``None`` when it did not run."""
        if not self.record.exists():
            return None
        return cast(object, json.loads(self.record.read_text(encoding="utf-8")))

    def test_dry_run_runs_real_command_without_approval_variable(self) -> None:
        self.assertEqual([], self.refusal_reasons(["--quiet", "git", "push", "-b", "a"], FORWARD, approve="x.y"))
        self.assertEqual(
            {
                "argv": [
                    str(self.fake_jj),
                    "--config",
                    "ui.editor=denied",
                    "git",
                    "push",
                    "-b",
                    "a",
                    "--dry-run",
                    "--color=never",
                ],
                "approve": None,
            },
            self.recorded(),
        )

    def test_unsafe_report_refuses(self) -> None:
        [reason] = self.refusal_reasons(["git", "push", "-b", "a"], BACKWARD)
        self.assertIn("move backward", reason)

    def test_failed_dry_run_refuses_without_claiming_a_violation(self) -> None:
        [reason] = self.refusal_reasons(["git", "push", "-b", "a"], "Error: No git remotes to push to\n", exit_status=1)
        self.assertIn("failed with exit status 1: Error: No git remotes to push to", reason)
        self.assertIn("this is not a policy violation", reason)

    def test_dry_run_and_approved_pushes_skip_the_check(self) -> None:
        self.assertEqual([], self.refusal_reasons(["git", "push", "-b", "a", "--dry-run"], BACKWARD))
        self.assertEqual([], self.refusal_reasons(["git", "push", "-b", "a"], BACKWARD, approve="jj.git-push"))
        self.assertIsNone(self.recorded())


JJ = shutil.which("jj")


@final
@unittest.skipIf(JJ is None, "jj is not on PATH")
class RealJjDryRunTests(unittest.TestCase):
    """The check against real jj and a local bare remote pins jj's report format.

    The remote's `main` starts at commit `b` (child of `a`); the working-copy
    commit `c` is a child of `b`.
    """

    @override
    def setUp(self) -> None:
        assert JJ is not None
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        config = root / "jj-config.toml"
        _ = config.write_text("", encoding="utf-8")
        self.environment = {
            "PATH": os.environ.get("PATH", ""),
            "HOME": str(root),
            "JJ_CONFIG": str(config),
            "JJ_USER": "Test",
            "JJ_EMAIL": "test@example.com",
        }
        self.remote = root / "remote.git"
        self.repo = str(root / "repo")
        self.tool = _jj_tool(JJ)

        _ = self.git("init", "--quiet", "--bare", str(self.remote))
        _ = self._run(JJ, "git", "init", self.repo)
        self.jj("git", "remote", "add", "origin", str(self.remote))
        self.jj("commit", "-m", "a")
        self.jj("commit", "-m", "b")
        self.jj("describe", "-m", "c")
        self.jj("bookmark", "create", "main", "-r", "@-")
        self.jj("git", "push", "-b", "main")
        self.remote_main = self.git("--git-dir", str(self.remote), "rev-parse", "main")

    def jj(self, *arguments: str) -> None:
        _ = self.jj_output(*arguments)

    def jj_output(self, *arguments: str) -> str:
        assert JJ is not None
        return self._run(JJ, "-R", self.repo, *arguments)

    def git(self, *arguments: str) -> str:
        return self._run("git", *arguments)

    def _run(self, *command: str) -> str:
        result = subprocess.run(command, env=self.environment, capture_output=True, text=True, check=False)
        self.assertEqual(0, result.returncode, f"{command}: {result.stderr}")
        return result.stdout.strip()

    def refusal_reasons(self, *argv: str) -> list[str]:
        refusals = evaluate(self.tool, ["-R", self.repo, *argv], self.environment)
        self.assertEqual(self.remote_main, self.git("--git-dir", str(self.remote), "rev-parse", "main"))
        return [reason for refusal in refusals for reason in refusal.reasons]

    def test_forward_new_and_unchanged_pushes_pass(self) -> None:
        self.assertEqual([], self.refusal_reasons("git", "push", "-b", "main"))
        self.jj("bookmark", "set", "main", "-r", "@")
        self.jj("bookmark", "create", "feature", "-r", "@-")
        self.assertEqual([], self.refusal_reasons("--quiet", "git", "push", "-b", "main", "--color=always"))
        self.assertEqual([], self.refusal_reasons("git", "push", "--named", "topic=@", "-b", "feature"))

    def test_backward_move_refuses_even_when_quiet(self) -> None:
        self.jj("bookmark", "set", "main", "-r", "@--", "--allow-backwards")
        [reason] = self.refusal_reasons("--quiet", "git", "push", "-b", "main")
        self.assertIn("`main` (move backward from", reason)

    def test_sideways_move_refuses(self) -> None:
        self.jj("new", "root()", "-m", "side")
        self.jj("bookmark", "set", "main", "-r", "@", "--allow-backwards")
        [reason] = self.refusal_reasons("git", "push", "-b", "main")
        self.assertIn("`main` (move sideways from", reason)

    def test_pushing_a_deleted_bookmark_refuses(self) -> None:
        self.jj("bookmark", "delete", "main")
        [reason] = self.refusal_reasons("git", "push", "-b", "main")
        self.assertIn("`main` (delete from", reason)

    def test_change_revset_with_several_commits_refuses(self) -> None:
        [reason] = self.refusal_reasons("git", "push", "-c", "all()")
        self.assertIn("but the command names only 1 target", reason)
        self.assertEqual("main", self.jj_output("bookmark", "list", "-T", 'name ++ "\\n"'))
