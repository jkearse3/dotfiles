#!/usr/bin/env python3
# pyright: reportImplicitRelativeImport=false, reportPrivateUsage=false
# pyright: reportUninitializedInstanceVariable=false

from __future__ import annotations

import io
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import cast, final, override
from unittest.mock import patch

from jj_description_format import cli


MESSY_DESCRIPTION = (
    "feat(scope): add a thing\n"
    "\n"
    "This body paragraph is deliberately written as one very long line that "
    "exceeds the seventy-two character body width limit and therefore needs "
    "rewrapping.\n"
)


def run(*arguments: str, cwd: Path, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    """Run a command in the test repository and capture its output."""
    return subprocess.run(
        arguments,
        cwd=cwd,
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


class RepositoryFixture(unittest.TestCase):
    """Provide each test with a temporary colocated Git and jj repository."""

    temporary_directory: TemporaryDirectory[str]
    repository: Path

    @override
    def setUp(self) -> None:
        """Create and initialize the temporary repository."""
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.repository = Path(self.temporary_directory.name).resolve()
        _ = run("git", "init", "-b", "main", ".", cwd=self.repository)
        _ = run("git", "config", "user.name", "Test User", cwd=self.repository)
        _ = run("git", "config", "user.email", "test@example.com", cwd=self.repository)
        _ = (self.repository / "tracked").write_text("initial\n")
        _ = run("git", "add", "tracked", cwd=self.repository)
        _ = run("git", "commit", "-m", "initial", cwd=self.repository)
        _ = run("jj", "git", "init", "--colocate", ".", cwd=self.repository)

    def describe(self, text: str) -> None:
        """Set the working-copy revision's description to TEXT verbatim."""
        _ = subprocess.run(
            ["jj", "describe", "-r", "@", "--stdin"],
            cwd=self.repository,
            check=True,
            input=text.encode(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def description(self, revision: str = "@") -> str:
        """Read REVISION's description verbatim."""
        return run(
            "jj", "log", "--no-graph", "-r", revision, "-T", "description", cwd=self.repository
        ).stdout.decode()

    def operation(self) -> bytes:
        """Return the current jj operation ID."""
        return run("jj", "op", "log", "--no-graph", "-n", "1", "-T", "id", cwd=self.repository).stdout

    def reformat(self, *, revision: str = "@", dry_run: bool = False) -> str:
        """Run a successful reformat and return its captured stdout."""
        output = io.StringIO()
        with patch("sys.stdout", output):
            self.assertEqual(
                cli.reformat(revision, dry_run=dry_run, cwd=self.repository), 0
            )
        return output.getvalue()


@final
class ReformatTests(RepositoryFixture):
    """Verify reformatting behavior against real jj repositories."""

    def test_rewrites_a_messy_description_to_format_output(self) -> None:
        """A messy description is rewritten to exactly commit-message format output."""
        self.describe(MESSY_DESCRIPTION)

        output = self.reformat()

        expected = subprocess.run(
            ["commit-message", "format"],
            check=True,
            input=MESSY_DESCRIPTION.encode(),
            stdout=subprocess.PIPE,
        ).stdout.decode()
        self.assertNotEqual(expected, MESSY_DESCRIPTION)
        self.assertEqual(self.description(), expected)
        self.assertIn("reformatted description of @", output)

    def test_second_run_is_a_no_op_without_a_new_operation(self) -> None:
        """An already-clean description produces no jj mutation."""
        self.describe(MESSY_DESCRIPTION)
        _ = self.reformat()
        operation = self.operation()

        output = self.reformat()

        self.assertIn("description already formatted", output)
        self.assertEqual(self.operation(), operation)

    def test_refuses_to_write_an_invalid_formatted_description(self) -> None:
        """A description still invalid after formatting aborts before any write."""
        subject = "x" * 73
        self.describe(f"{subject}\n")
        errors = io.StringIO()

        with patch("sys.stderr", errors):
            with self.assertRaisesRegex(
                cli.DescriptionFormatError, "failed validation"
            ):
                _ = cli.reformat("@", cwd=self.repository)

        self.assertIn("- line 1: subject is 73 characters", errors.getvalue())
        self.assertEqual(self.description(), f"{subject}\n")

    def test_rejects_an_empty_description(self) -> None:
        """An empty description is an error, not a no-op."""
        with self.assertRaisesRegex(cli.DescriptionFormatError, "has no description"):
            _ = cli.reformat("@", cwd=self.repository)

    def test_dry_run_prints_a_diff_without_writing(self) -> None:
        """A dry run shows the unified diff and leaves the description alone."""
        self.describe(MESSY_DESCRIPTION)

        output = self.reformat(dry_run=True)

        self.assertIn("--- current", output)
        self.assertIn("+++ formatted", output)
        self.assertEqual(self.description(), MESSY_DESCRIPTION)

    def test_dry_run_reports_a_clean_description(self) -> None:
        """A dry run on a clean description prints the no-change notice."""
        self.describe("clean subject\n")

        output = self.reformat(dry_run=True)

        self.assertIn("description already formatted", output)

    def test_rejects_a_nonexistent_revset(self) -> None:
        """A revset jj cannot resolve surfaces jj's own error."""
        with self.assertRaisesRegex(cli.DescriptionFormatError, "no-such-bookmark"):
            _ = cli.reformat("no-such-bookmark", cwd=self.repository)

    def test_rejects_a_multi_revision_revset(self) -> None:
        """A revset matching several revisions is rejected before any write."""
        self.describe("first subject\n")
        _ = run("jj", "new", cwd=self.repository)
        self.describe("second subject\n")

        with self.assertRaisesRegex(
            cli.DescriptionFormatError, "exactly one revision"
        ):
            _ = cli.reformat("@ | @-", cwd=self.repository)

        self.assertEqual(self.description("@-"), "first subject\n")
        self.assertEqual(self.description("@"), "second subject\n")

    def test_defaults_to_the_working_copy_revision(self) -> None:
        """The CLI defaults the target revision to @."""
        parser = cli.create_parser()

        arguments = parser.parse_args([])

        self.assertEqual(cast(str, arguments.revision), "@")
        self.assertFalse(cast(bool, arguments.dry_run))
        self.assertIsNone(cast("int | None", arguments.subject_width))
        self.assertIsNone(cast("int | None", arguments.body_width))


if __name__ == "__main__":
    _ = unittest.main()
