#!/usr/bin/env python3
# pyright: reportImplicitRelativeImport=false, reportPrivateUsage=false
# pyright: reportUninitializedInstanceVariable=false

from __future__ import annotations

from collections.abc import MutableMapping
from contextlib import AbstractContextManager

import io
import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import final, override
from unittest.mock import patch

from jj_worktree_add import cli


def run(*arguments: str, check: bool = True, cwd: Path | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(arguments, cwd=cwd, check=check, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


class RepositoryFixture(unittest.TestCase):
    temporary_directory: TemporaryDirectory[str]
    root: Path
    primary: Path

    @override
    def setUp(self) -> None:
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name).resolve()
        home = self.root / "home"
        (home / ".config").mkdir(parents=True)
        # `patch.dict` is untyped, so bind it to the context-manager protocol it
        # implements and let `enterContext` own the teardown; calling `start` and
        # `stop` through the unannotated value spreads Any into `addCleanup`.
        environment: AbstractContextManager[MutableMapping[str, str]] = patch.dict(
            os.environ,
            {
                "HOME": str(home),
                "XDG_CONFIG_HOME": str(home / ".config"),
                "XDG_CACHE_HOME": str(home / ".cache"),
                "XDG_STATE_HOME": str(home / ".state"),
            },
        )
        self.enterContext(environment)
        self.primary = self.root / "primary"
        self.primary.mkdir()
        _ = run("git", "init", str(self.primary))
        _ = run("git", "-C", str(self.primary), "config", "user.name", "Test User")
        _ = run("git", "-C", str(self.primary), "config", "user.email", "test@example.com")
        _ = (self.primary / "tracked").write_text("initial\n")
        _ = run("git", "-C", str(self.primary), "add", "tracked")
        _ = run("git", "-C", str(self.primary), "commit", "-m", "initial")
        _ = run("jj", "git", "init", "--colocate", ".", cwd=self.primary)


@final
class AddTests(RepositoryFixture):
    def test_creates_detached_worktree_at_default_revision(self) -> None:
        source = run("jj", "-R", str(self.primary), "log", "--no-graph", "-r", "@", "-T", "commit_id").stdout
        created = cli.add("feature", start=self.primary)
        self.assertEqual(created, self.primary / ".jj-worktrees" / "feature")
        self.assertEqual(run("git", "-C", str(created), "rev-parse", "HEAD").stdout.strip(), source)
        self.assertNotEqual(run("git", "-C", str(created), "symbolic-ref", "-q", "HEAD", check=False).returncode, 0)
        private = Path(run("git", "-C", str(created), "rev-parse", "--absolute-git-dir").stdout.decode().strip())
        self.assertTrue(os.path.samefile(run("jj", "-R", str(created), "git", "root").stdout.decode().strip(), private))

    def test_accepts_revset_from_linked_worktree_and_preserves_gitignore(self) -> None:
        managed = self.primary / ".jj-worktrees"
        managed.mkdir()
        gitignore = managed / ".gitignore"
        _ = gitignore.write_bytes(b"# retained")
        first = cli.add("first", "@-", self.primary)
        second = cli.add("second", "@-", first)
        self.assertEqual(second.parent, managed)
        self.assertEqual(gitignore.read_bytes(), b"# retained\n*\n")

    def test_rejects_invalid_names_and_ambiguous_revisions_before_creation(self) -> None:
        for name in ("", ".", "..", ".gitignore", "nested/name", "line\nbreak"):
            with self.subTest(name=name), self.assertRaises(cli.WorktreeAddError):
                _ = cli.add(name, "@-", self.primary)
        with self.assertRaises(cli.WorktreeAddError):
            _ = cli.add("ambiguous", "root() | @", self.primary)
        self.assertFalse((self.primary / ".jj-worktrees" / "ambiguous").exists())

    def test_preserves_worktree_when_jj_ensure_fails(self) -> None:
        real_run = cli._run

        def fail_ensure(command: list[str] | tuple[str, ...], *, cwd: Path | None = None) -> bytes:
            if command[0] == "jj-ensure":
                raise cli.WorktreeAddError("simulated failure")
            return real_run(command, cwd=cwd)

        with patch.object(cli, "_run", side_effect=fail_ensure):
            with self.assertRaisesRegex(cli.WorktreeAddError, "preserved; recover with: jj-ensure"):
                _ = cli.add("retained", "@-", self.primary)
        retained = self.primary / ".jj-worktrees" / "retained"
        self.assertTrue(retained.is_dir())
        self.assertIn(retained, [Path(line.split()[0]) for line in run("git", "-C", str(self.primary), "worktree", "list").stdout.decode().splitlines()])


@final
class CliTests(unittest.TestCase):
    def test_cli_prints_only_path_and_reports_concise_error(self) -> None:
        output = io.StringIO()
        error = io.StringIO()
        with patch.object(cli, "add", return_value=Path("/created")) as add, patch("sys.stdout", output), patch("sys.stderr", error):
            self.assertEqual(cli.main(["name", "-r", "@-"]), 0)
        add.assert_called_once_with("name", "@-")
        self.assertEqual(output.getvalue(), "/created\n")
        self.assertEqual(error.getvalue(), "")

        output = io.StringIO()
        error = io.StringIO()
        with patch.object(cli, "add", side_effect=cli.WorktreeAddError("failed")), patch("sys.stdout", output), patch("sys.stderr", error):
            with self.assertRaises(SystemExit) as status:
                _ = cli.main(["name"])
        self.assertEqual(status.exception.code, 1)
        self.assertEqual(output.getvalue(), "")
        self.assertEqual(error.getvalue(), "error: failed\n")

    def test_cli_defaults_revision_to_current_commit(self) -> None:
        with patch.object(cli, "add", return_value=Path("/created")) as add:
            self.assertEqual(cli.main(["name"]), 0)
        add.assert_called_once_with("name", "@")

    def test_help_documents_contract(self) -> None:
        help_text = cli.create_parser().format_help()
        for expected in ("NAME", "REVSET", ".jj-worktrees/NAME", "defaults to @", "native git"):
            self.assertIn(expected, help_text)
