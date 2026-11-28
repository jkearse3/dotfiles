"""Tests for CliRex, the adapter that runs the `rex` CLI.

They put a fake `rex` executable first on PATH. It records each call's
arguments, refuses any call that could start a Rex server (one not led by
`--autostart=false`), and replies with the output each test sets, shaped like
the real Rex's replies.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from typing import cast, override
from unittest import mock

from rex_agents.rex import CliRex, OpenedTab, Placement, RexError, Tab

# The fake runs under this test's own interpreter, because the Nix build
# sandbox may have no /usr/bin/env to find one.
_FAKE_REX = f"""#!{sys.executable} -I
import json
import sys
from pathlib import Path

here = Path(__file__).parent
with open(here / "calls.jsonl", "a") as calls:
    calls.write(json.dumps(sys.argv[1:]) + "\\n")
if sys.argv[1:2] != ["--autostart=false"]:
    sys.stderr.write("fake rex: missing --autostart=false\\n")
    sys.exit(64)
reply = json.loads((here / "reply.json").read_text())
sys.stdout.write(reply["stdout"])
sys.stderr.write(reply["stderr"])
sys.exit(reply["status"])
"""

SESSION = "session:00000000-0000-0000-0000-000000000001"
BLOCK = "block:00000000-0000-0000-0000-00000000000b"
WINDOW = "window:00000000-0000-0000-0000-00000000000a"
OTHER_WINDOW = "window:00000000-0000-0000-0000-00000000000c"


class CliRexTestCase(unittest.TestCase):
    """Runs CliRex against the fake `rex`, replying with success by default."""

    @override
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.bin = Path(directory.name)

        rex = self.bin / "rex"
        _ = rex.write_text(_FAKE_REX)
        rex.chmod(0o755)
        self.reply()

        path = mock.patch.dict(os.environ, {"PATH": f"{self.bin}{os.pathsep}{os.environ.get('PATH', '')}"})
        _ = path.start()
        self.addCleanup(path.stop)

        self.rex = CliRex()

    def reply(self, *, stdout: str = "", stderr: str = "", status: int = 0) -> None:
        """Make every later `rex` call print STDOUT and STDERR and exit STATUS."""
        reply = {"stdout": stdout, "stderr": stderr, "status": status}
        _ = (self.bin / "reply.json").write_text(json.dumps(reply))

    def reply_json(self, data: object) -> None:
        self.reply(stdout=json.dumps(data) + "\n")

    def calls(self) -> list[list[str]]:
        """Return each `rex` call's arguments, in call order."""
        lines = (self.bin / "calls.jsonl").read_text().splitlines()
        return [cast(list[str], json.loads(line)) for line in lines]

    def assert_one_call(self, *args: str) -> None:
        self.assertEqual(self.calls(), [["--autostart=false", *args]])


class CallTest(CliRexTestCase):
    def test_placement_reads_session_and_window(self) -> None:
        self.reply_json(
            {
                "session_id": SESSION,
                "block": {"block_id": BLOCK, "window_id": WINDOW, "kind": "terminal"},
            }
        )
        self.assertEqual(self.rex.placement(BLOCK), Placement(session=SESSION, window=WINDOW))
        self.assert_one_call("block", "inspect", BLOCK, "--json")

    def test_tabs_keep_tab_order(self) -> None:
        self.reply_json(
            {
                "windows": [
                    {"window_id": OTHER_WINDOW, "label": "parent"},
                    {"window_id": WINDOW, "label": "probe"},
                ]
            }
        )
        self.assertEqual(
            self.rex.tabs(SESSION),
            [Tab(window=OTHER_WINDOW, label="parent"), Tab(window=WINDOW, label="probe")],
        )
        self.assert_one_call("window", "ls", "-s", SESSION, "--json")

    def test_open_tab_keeps_it_open_in_the_background(self) -> None:
        self.reply_json({"window_id": WINDOW, "block_ids": [BLOCK], "revision": 7})
        opened = self.rex.open_tab(SESSION, "probe", "/work", ["claude", "--name", "probe"])
        self.assertEqual(opened, OpenedTab(block=BLOCK, window=WINDOW))
        self.assert_one_call(
            "window", "new", "probe", "-s", SESSION, "-c", "/work",
            "--keep-open", "--focus=false", "--json", "--", "claude", "--name", "probe",
        )  # fmt: skip

    def test_move_tab_after(self) -> None:
        self.rex.move_tab_after(SESSION, WINDOW, OTHER_WINDOW)
        self.assert_one_call("window", "move", "-s", SESSION, WINDOW, "--after", OTHER_WINDOW)

    def test_rename_tab(self) -> None:
        self.rex.rename_tab(SESSION, WINDOW, "✓ probe")
        self.assert_one_call("window", "rename", "-s", SESSION, WINDOW, "✓ probe")

    def test_close_block(self) -> None:
        self.rex.close_block(BLOCK)
        self.assert_one_call("block", "close", BLOCK)

    def test_process_returns_the_reply(self) -> None:
        reply: dict[str, object] = {
            "last_exit": {"exit_code": 3, "error": "exit status 3"},
            "home": "/Users/someone",
        }
        self.reply_json(reply)
        self.assertEqual(self.rex.process(BLOCK), reply)
        self.assert_one_call("block", "call", "-b", BLOCK, "process")

    def test_program_status_returns_the_records(self) -> None:
        record: dict[str, object] = {
            "state": "blocked",
            "updated_at": "2026-11-28T07:00:00Z",
            "kind": "permission",
            "msg": "trust this folder",
        }
        self.reply_json({"records": [record]})
        self.assertEqual(self.rex.program_status(BLOCK), [record])
        self.assert_one_call("block", "call", "-b", BLOCK, "program_status")

    def test_screen_returns_the_capture(self) -> None:
        self.reply(stdout="$ claude\nWorking…\n")
        self.assertEqual(self.rex.screen(BLOCK), "$ claude\nWorking…\n")
        self.assert_one_call("block", "capture", "-b", BLOCK, "--trim")


class FailureTest(CliRexTestCase):
    def assert_rex_error(self, call: str, message: str, *, not_found: bool) -> None:
        """Assert that the CliRex method named CALL on BLOCK raises this RexError."""
        with self.assertRaises(RexError) as raised:
            _ = getattr(self.rex, call)(BLOCK)
        self.assertEqual(raised.exception.message, message)
        self.assertEqual(raised.exception.not_found, not_found)

    def test_missing_target_is_not_found(self) -> None:
        self.reply(stderr=f'Error: block target "{BLOCK}" not found\n', status=3)
        self.assert_rex_error("process", f'block target "{BLOCK}" not found', not_found=True)

    def test_exit_3_is_not_found_whatever_the_message(self) -> None:
        self.reply(stderr="Error: no such block\n", status=3)
        self.assert_rex_error("process", "no such block", not_found=True)

    def test_not_found_message_is_not_found_whatever_the_status(self) -> None:
        self.reply(stderr=f'Error: window target "{WINDOW}" not found\n', status=1)
        self.assert_rex_error("close_block", f'window target "{WINDOW}" not found', not_found=True)

    def test_no_server_is_not_not_found(self) -> None:
        message = "no Rex server is running at /tmp/rex.sock, and autostart is disabled"
        self.reply(stderr=f"Error: {message}\n", status=4)
        self.assert_rex_error("process", message, not_found=False)

    def test_silent_failure_names_the_status(self) -> None:
        self.reply(status=5)
        self.assert_rex_error("close_block", "rex exited with status 5", not_found=False)

    def test_non_json_output(self) -> None:
        self.reply(stdout="Rex 1.0\n")
        with self.assertRaisesRegex(RexError, "^rex block call: unreadable output"):
            _ = self.rex.process(BLOCK)

    def test_non_object_reply(self) -> None:
        self.reply_json([])
        with self.assertRaisesRegex(RexError, "^rex block call: unreadable output: not a JSON object$"):
            _ = self.rex.process(BLOCK)

    def test_open_tab_reply_without_block_ids(self) -> None:
        self.reply_json({"window_id": WINDOW, "revision": 7})
        with self.assertRaisesRegex(RexError, "no block_ids"):
            _ = self.rex.open_tab(SESSION, "probe", "/work", ["claude"])

    def test_placement_reply_without_window(self) -> None:
        self.reply_json({"session_id": SESSION, "block": {"block_id": BLOCK}})
        with self.assertRaisesRegex(RexError, "no string window_id"):
            _ = self.rex.placement(BLOCK)

    def test_missing_rex_cannot_run(self) -> None:
        empty = tempfile.TemporaryDirectory()
        self.addCleanup(empty.cleanup)
        with mock.patch.dict(os.environ, {"PATH": empty.name}):
            with self.assertRaisesRegex(RexError, "^cannot run rex: "):
                _ = self.rex.process(BLOCK)


if __name__ == "__main__":
    _ = unittest.main()
