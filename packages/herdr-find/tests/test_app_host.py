"""herdr-find driving the Herdr desktop app (--host app) through fake herdr-app and hc executables."""

from __future__ import annotations

import http.client
import json
import os
import pty
import re
import shlex
import shutil
import signal
import socket
import subprocess
import tempfile
import termios
import threading
import time
import unittest
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path
from typing import cast, final, override

CLI = os.environ["HERDR_FIND"]

PICKER_KEY_HINTS = "ctrl-a agents  ctrl-w workspaces  ctrl-r refresh  ctrl-o preview  ctrl-u/ctrl-d scroll preview"

ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")

# Stands in for fzf, as in test_herdr_find.py: records its arguments, one per
# NUL-terminated entry, in $FAKE_FZF_ARGV and its input rows in
# $FAKE_FZF_INPUT, then prints input row number $FAKE_FZF_CHOICE and exits 0,
# or, with no choice, exits 130 as fzf does on Esc.
FAKE_FZF = """\
#!/bin/sh
printf '%s\\0' "$@" > "$FAKE_FZF_ARGV"
cat > "$FAKE_FZF_INPUT"
if [ -n "${FAKE_FZF_CHOICE:-}" ]; then
  sed -n "${FAKE_FZF_CHOICE}p" "$FAKE_FZF_INPUT"
  exit 0
fi
exit 130
"""

# Each fake records its call as "<program> <arguments>" in $STUB_LOG.
#
# herdr-app: ls prints $APP_STUB_WORLD, or with $APP_STUB_NO_WINDOW set fails as
# herdr-app does when no window is open; do succeeds, unless its command is
# $APP_STUB_FAIL_DO, when it replies with $APP_STUB_ERROR as herdr-app does.
FAKE_HERDR_APP = """\
#!/bin/sh
printf 'herdr-app %s\\n' "$*" >> "$STUB_LOG"
case "$1" in
  ls)
    if [ -n "${APP_STUB_NO_WINDOW:-}" ]; then
      printf '%s\\n' 'herdr-app: no Herdr window at /app/herdr-app.sock: No such file or directory (os error 2)' >&2
      exit 2
    fi
    printf '%s\\n' "$APP_STUB_WORLD" ;;
  do)
    if [ "$2" = "${APP_STUB_FAIL_DO:-}" ]; then
      printf '{\\n  "error": "%s"\\n}\\n' "$APP_STUB_ERROR"
      exit 1
    fi
    printf '{\\n  "ok": true\\n}\\n' ;;
  *)
    exit 2 ;;
esac
"""

# hc: ls prints $HC_STUB_TERMINALS under "terminals", get prints
# $HC_STUB_RECORD, read prints $HC_STUB_READ. The command named by
# $HC_STUB_FAIL fails as hc does when its output is piped.
FAKE_HC = """\
#!/bin/sh
printf 'hc %s\\n' "$*" >> "$STUB_LOG"
if [ "$1" = "${HC_STUB_FAIL:-}" ]; then
  printf '%s\\n' '{"error":{"kind":"not_found","hint":"see hc ls","message":"no terminal t9"}}' >&2
  exit 1
fi
case "$1" in
  ls) printf '{"terminals":%s,"hidden_finished":0}\\n' "$HC_STUB_TERMINALS" ;;
  get) printf '%s\\n' "$HC_STUB_RECORD" ;;
  read) printf '%s' "$HC_STUB_READ" ;;
  *) exit 2 ;;
esac
"""

# Stands in for herdr-app as the app picker's popup sees it: closing an
# overlay starts reset for it in the background, as the popup mod's
# closeCommand does, then the shared fake herdr-app, {shared}, handles the call.
CLOSING_HERDR_APP = """\
#!/bin/sh
if [ "$1 $2" = "do overlay.close" ]; then
  overlay=$(printf '%s' "$3" | sed -n 's/.*"id": "\\([^"]*\\)".*/\\1/p')
  "$HERDR_FIND_BIN" reset --overlay "$overlay" < /dev/null > /dev/null 2>&1 &
fi
exec {shared} "$@"
"""

# The TUI's herdr, named by $HERDR_BIN_PATH, which an app-host command must never call.
FAKE_HERDR = """\
#!/bin/sh
printf 'herdr %s\\n' "$*" >> "$STUB_LOG"
exit 1
"""


def pane_terminal(address: str, status: str | None = None, app: str | None = None) -> dict[str, object]:
    """Return a terminal shown in a pane, shaped like one in ``herdr-app ls``."""
    return {
        "terminal": address,
        "pane": f"p-{address}",
        "status": status,
        "app": app,
        "name": f"name {address}",
        "sub_agents": [],
    }


def space(
    space_id: str,
    name: str,
    folder: str,
    tabs: Sequence[tuple[str, Sequence[dict[str, object]]]],
    **fields: object,
) -> dict[str, object]:
    """Return a space shaped like one in ``herdr-app ls``, with TABS as (name, pane terminals)."""
    return {
        "id": space_id,
        "name": name,
        "folder": folder,
        "machine": None,
        "active": False,
        "tabs": [
            {
                "id": f"tb-{space_id}-{index}",
                "name": tab_name,
                "active": index == 0,
                "settled": False,
                "terminals": list(terminals),
            }
            for index, (tab_name, terminals) in enumerate(tabs)
        ],
        **fields,
    }


def core_terminal(address: str, status: str | None = None, **fields: object) -> dict[str, object]:
    """Return a terminal shaped like one in ``hc ls --json``, which leaves out absent fields."""
    record: dict[str, object] = {
        "address": address,
        "state": "live",
        "turn": 0,
        "cwd": "/srv/project",
        "agent": "fish",
        **fields,
    }
    if status is not None:
        record["status"] = status
    return record


class AppStubTestCase(unittest.TestCase):
    """Runs the CLI with fake herdr-app, hc, and herdr, in a throwaway home.

    The package wrapper appends herdr-app and hc to PATH, so the fakes first
    on PATH win.
    """

    @override
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        self.home = self.root / "home"
        self.home.mkdir()
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        for name, script in (("herdr-app", FAKE_HERDR_APP), ("hc", FAKE_HC), ("herdr", FAKE_HERDR)):
            fake = bin_dir / name
            _ = fake.write_text(script)
            fake.chmod(0o755)
        self.log = self.root / "calls.log"

        self.env = {
            key: value
            for key, value in os.environ.items()
            if key not in ("HERDR_ENV", "HC_TERMINAL_ID", "HERDR_PLUGIN_CONTEXT_JSON")
            and not key.startswith("FZF_")
        }
        self.env |= {
            "HOME": str(self.home),
            "PATH": f"{bin_dir}:{os.environ.get('PATH', '')}",
            # The package wrapper puts the real herdr first on PATH.
            "HERDR_BIN_PATH": str(bin_dir / "herdr"),
            "STUB_LOG": str(self.log),
            "APP_STUB_WORLD": json.dumps(self.world()),
            "HC_STUB_TERMINALS": json.dumps(self.terminals()),
            "HC_STUB_RECORD": json.dumps({"address": "t1", "labels": {"herdr.space": "sp1", "herdr.tab": "tb-sp1-0"}}),
            "HC_STUB_READ": "",
        }

    def world(self) -> dict[str, object]:
        """Return the app window: dotfiles (a blocked claude and a shell), notes (an idle pi), and a remote space."""
        return {
            "spaces": [
                space(
                    "sp1",
                    "dotfiles",
                    str(self.home / "dotfiles"),
                    [("editor", [pane_terminal("t1", "blocked", "claude-code"), pane_terminal("t2")]), ("2", [])],
                ),
                space("sp2", "notes", "/srv/notes", [("1", [pane_terminal("t3", "idle", "pi")])]),
                space(
                    "rohan/sp9",
                    "remote",
                    "/home/x",
                    [("1", [pane_terminal("rohan/t9", "working", "pi")])],
                    machine="rohan",
                ),
            ],
            "recent": [],
        }

    def terminals(self) -> list[dict[str, object]]:
        """Return the core's live terminals for world(), plus a sub-agent and a paneless failed agent."""
        return [
            core_terminal("t1", "blocked", agent="claude-code", cwd=str(self.home / "dotfiles"), name="fix"),
            core_terminal("t2"),
            # The app shows t3 as idle once seen, though pi's last word was "done".
            core_terminal("t3", "done", agent="pi", cwd="/srv/notes"),
            core_terminal("t4", "working", agent="claude-code", parent="t1", name="helper"),
            core_terminal("t5", "error", agent="codex"),
            core_terminal("rohan/t9", "working", agent="pi"),
        ]

    def run_cli(
        self, arguments: Sequence[str], env: Mapping[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        _ = self.log.write_text("")
        return subprocess.run(
            [CLI, *arguments],
            env={**self.env, **(env if env is not None else {})},
            text=True,
            capture_output=True,
            check=False,
        )

    def calls(self) -> list[str]:
        return self.log.read_text().splitlines()

    def targets(self, stdout: str) -> list[str]:
        return [line.split("\t")[0] for line in stdout.splitlines()]


@final
class HostDetectionTests(AppStubTestCase):
    def test_default_host_follows_the_environment(self) -> None:
        cases: list[tuple[dict[str, str], str]] = [
            # environment, expected first call
            ({"HC_TERMINAL_ID": "t1"}, "herdr-app ls"),
            ({"HC_TERMINAL_ID": "t1", "HERDR_ENV": "1"}, "herdr agent list"),
            ({"HC_TERMINAL_ID": "t1", "HERDR_ENV": "0"}, "herdr-app ls"),
            ({"HERDR_ENV": "1"}, "herdr agent list"),
            ({}, "herdr agent list"),
        ]
        for env, first_call in cases:
            with self.subTest(env=env):
                _ = self.run_cli(["rows", "--caller-workspace", "sp1"], env)
                self.assertEqual(self.calls()[0], first_call)

    def test_host_option_overrides_the_environment(self) -> None:
        _ = self.run_cli(["rows", "--host", "app"])
        self.assertEqual(self.calls(), ["herdr-app ls", "hc ls --json"])
        _ = self.run_cli(["rows", "--host", "tui"], {"HC_TERMINAL_ID": "t1"})
        self.assertEqual(self.calls()[0], "herdr agent list")

    def test_callbacks_name_a_host_the_environment_would_not_default_to(self) -> None:
        cases = [
            # environment, host, the rows command's options after --picker-header
            ({"HC_TERMINAL_ID": "t1"}, "tui", " --host tui"),
            ({"HC_TERMINAL_ID": "t1"}, "app", " --host app"),
            ({"HERDR_ENV": "1"}, "app", " --host app"),
            ({"HERDR_ENV": "1"}, "tui", ""),
        ]
        for env, host, options in cases:
            with self.subTest(env=env, host=host):
                result = self.run_cli(["reload-action", "refresh", "--host", host], {**env, "FZF_PROMPT": "> "})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(result.stdout.endswith(f" rows --picker-header{options}\n"), result.stdout)


@final
class AppRowsTests(AppStubTestCase):
    def rows(self, *arguments: str, env: Mapping[str, str] | None = None) -> list[tuple[str, list[str]]]:
        """Return each printed row's target and uncoloured display cells."""
        result = self.run_cli(["rows", "--host", "app", *arguments], env)
        self.assertEqual(result.returncode, 0, result.stderr)
        parsed: list[tuple[str, list[str]]] = []
        for line in result.stdout.splitlines():
            target, display = line.split("\t")
            parsed.append((target, re.split(r" {2,}", ANSI_ESCAPE.sub("", display))))
        return parsed

    def test_rows_list_agents_by_status_then_spaces_in_sidebar_order(self) -> None:
        self.assertEqual(
            self.rows(),
            [
                ("agent:t1", ["blocked", "claude-code", "fix", "dotfiles", "~/dotfiles"]),
                ("agent:t5", ["blocked", "codex", "/srv/project"]),
                ("agent:t3", ["idle", "pi", "notes", "/srv/notes"]),
                ("agent:t4", ["working", "claude-code", "helper", "dotfiles", "/srv/project"]),
                ("workspace:sp1", ["dotfiles", "~/dotfiles", "1 blocked, 1 working"]),
                ("workspace:sp2", ["notes", "/srv/notes", "1 idle"]),
            ],
        )
        self.assertEqual(self.calls(), ["herdr-app ls", "hc ls --json"])

    def test_caller_options_sort_the_callers_rows_last(self) -> None:
        result = self.run_cli(["rows", "--host", "app", "--caller-workspace", "sp1", "--caller-pane", "t1"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.targets(result.stdout),
            ["agent:t5", "agent:t3", "agent:t4", "agent:t1", "workspace:sp2", "workspace:sp1"],
        )
        self.assertEqual(self.calls(), ["herdr-app ls", "hc ls --json"])

    def test_caller_defaults_to_the_terminal_the_cli_runs_in(self) -> None:
        result = self.run_cli(["rows"], {"HC_TERMINAL_ID": "t1"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.targets(result.stdout),
            ["agent:t5", "agent:t3", "agent:t4", "agent:t1", "workspace:sp2", "workspace:sp1"],
        )
        self.assertEqual(self.calls(), ["hc get t1 --json", "herdr-app ls", "hc ls --json"])

    def test_only_limits_rows_to_one_group(self) -> None:
        result = self.run_cli(["rows", "--host", "app", "--only", "workspaces"])
        self.assertEqual(self.targets(result.stdout), ["workspace:sp1", "workspace:sp2"])
        result = self.run_cli(["rows", "--host", "app", "--only", "agents"])
        self.assertEqual(self.targets(result.stdout), ["agent:t1", "agent:t5", "agent:t3", "agent:t4"])

    def test_no_window_fails_clearly_without_calling_hc(self) -> None:
        result = self.run_cli(["rows", "--host", "app"], {"APP_STUB_NO_WINDOW": "1"})
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertEqual(
            result.stderr,
            "error: herdr-app ls failed: herdr-app: no Herdr window at /app/herdr-app.sock: "
            + "No such file or directory (os error 2)\n",
        )
        self.assertEqual(self.calls(), ["herdr-app ls"])

    def test_picker_header_reports_a_failure_in_its_place(self) -> None:
        result = self.run_cli(["rows", "--host", "app", "--picker-header"], {"HC_STUB_FAIL": "ls"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            ANSI_ESCAPE.sub("", result.stdout),
            "\terror: hc ls --json failed: no terminal t9\n",
        )

    def test_control_characters_cannot_break_rows(self) -> None:
        hostile = "a\tb\nc\x1b[31m"
        world = self.world()
        world["spaces"] = [space("sp1", hostile, "/srv/x\ny", [("1", [pane_terminal("t1", "idle", hostile)])])]
        terminals = [core_terminal("t1", "idle\t", agent=hostile, name=hostile)]
        result = self.run_cli(
            ["rows", "--host", "app"],
            {"APP_STUB_WORLD": json.dumps(world), "HC_STUB_TERMINALS": json.dumps(terminals)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(len(lines), 2)
        for line in lines:
            self.assertEqual(line.count("\t"), 1, line)
            self.assertNotIn("\x1b[31m", line)


@final
class AppPreviewTests(AppStubTestCase):
    def test_agent_preview_prints_its_screen_and_history(self) -> None:
        result = self.run_cli(["preview", "--host", "app", "agent:t1"], {"HC_STUB_READ": "line 1\nline 2\n"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "line 1\nline 2\n")
        self.assertEqual(self.calls(), ["hc read t1 --lines 40"])

    def test_space_preview_lists_name_folder_and_tabs_with_agents(self) -> None:
        result = self.run_cli(["preview", "--host", "app", "workspace:sp1"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            ANSI_ESCAPE.sub("", result.stdout).splitlines(),
            [
                "dotfiles",
                "~/dotfiles",
                "editor",
                "  claude-code  blocked  name t1",
                "  shell        unknown  name t2",
                "2",
            ],
        )
        self.assertEqual(self.calls(), ["herdr-app ls"])

    def test_failures_are_reported(self) -> None:
        cases: list[tuple[str, dict[str, str], str]] = [
            ("agent:t9", {"HC_STUB_FAIL": "read"}, "error: hc read t9 --lines 40 failed: no terminal t9\n"),
            ("workspace:sp9", {}, "error: the Herdr app has no space 'sp9'\n"),
            ("workspace:rohan/sp9", {}, "error: the Herdr app has no space 'rohan/sp9'\n"),
        ]
        for target, env, stderr in cases:
            with self.subTest(target=target):
                result = self.run_cli(["preview", "--host", "app", target], env)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, stderr)


@final
class AppPickTests(AppStubTestCase):
    @override
    def setUp(self) -> None:
        super().setUp()
        fake_fzf = self.root / "fzf"
        _ = fake_fzf.write_text(FAKE_FZF)
        fake_fzf.chmod(0o755)
        self.fzf_argv = self.root / "fzf.argv"
        self.fzf_input = self.root / "fzf.input"
        self.env |= {
            "HERDR_FIND_FZF_PATH": str(fake_fzf),
            "FAKE_FZF_ARGV": str(self.fzf_argv),
            "FAKE_FZF_INPUT": str(self.fzf_input),
        }

    # The options an app launcher passes for a picker opened from terminal t1 of space sp1.
    LAUNCHER_OPTIONS = ("--host", "app", "--caller-workspace", "sp1", "--caller-pane", "t1")

    def run_pick(self, env: Mapping[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        return self.run_cli(["pick", *self.LAUNCHER_OPTIONS], env)

    def fzf_arguments(self) -> list[str]:
        return self.fzf_argv.read_text().split("\0")[:-1]

    def fzf_input_targets(self) -> list[str]:
        header, *listed = self.fzf_input.read_text().splitlines()
        self.assertEqual(header, f"\t{PICKER_KEY_HINTS}")
        return [line.split("\t")[0] for line in listed]

    def binding(self, key: str) -> str:
        actions = [
            argument.removeprefix(f"--bind={key}:")
            for argument in self.fzf_arguments()
            if argument.startswith(f"--bind={key}:")
        ]
        self.assertEqual(len(actions), 1, self.fzf_arguments())
        return actions[0]

    def run_shell(self, command: str, env: Mapping[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        """Run COMMAND as fzf's --with-shell runs a binding's command, from a popup terminal with no labels."""
        _ = self.log.write_text("")
        return subprocess.run(
            ["/bin/sh", "-c", command],
            env={**self.env, "HC_TERMINAL_ID": "t8", **(env if env is not None else {})},
            text=True,
            capture_output=True,
            check=False,
        )

    def test_enter_focuses_the_chosen_agent(self) -> None:
        # Input line 1 is the header line; line 2 the first agent, t5.
        result = self.run_pick({"FAKE_FZF_CHOICE": "2"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["herdr-app ls", "hc ls --json", 'herdr-app do agent.focus {"terminal": "t5"}'])

    def test_enter_selects_the_chosen_space(self) -> None:
        result = self.run_pick({"FAKE_FZF_CHOICE": "6"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["herdr-app ls", "hc ls --json", 'herdr-app do space.select {"id": "sp2"}'])

    def test_closing_without_a_choice_changes_nothing(self) -> None:
        result = self.run_pick()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["herdr-app ls", "hc ls --json"])

    def test_focus_failure_is_shown_until_enter(self) -> None:
        env = {"FAKE_FZF_CHOICE": "2", "APP_STUB_FAIL_DO": "agent.focus", "APP_STUB_ERROR": "no terminal t5"}
        result = self.run_pick(env)
        self.assertEqual(result.returncode, 1)
        self.assertIn("agent.focus", result.stderr)
        self.assertIn("failed: no terminal t5", result.stderr)
        self.assertTrue(result.stderr.endswith("Press enter to close."), result.stderr)

    def test_callers_rows_sort_last(self) -> None:
        _ = self.run_pick()
        self.assertEqual(
            self.fzf_input_targets(),
            ["agent:t5", "agent:t3", "agent:t4", "agent:t1", "workspace:sp2", "workspace:sp1"],
        )

    def test_caller_defaults_to_the_terminal_the_picker_runs_in(self) -> None:
        result = self.run_cli(["pick", "--host", "app"], {"HC_TERMINAL_ID": "t1"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["hc get t1 --json", "herdr-app ls", "hc ls --json"])
        reload_arguments = " reload-action refresh --host app --caller-workspace sp1 --caller-pane t1"
        self.assertTrue(self.binding("ctrl-r").endswith(reload_arguments), self.binding("ctrl-r"))

    def test_preview_callback_drives_the_app(self) -> None:
        _ = self.run_pick()
        previews = [
            argument.removeprefix("--preview=")
            for argument in self.fzf_arguments()
            if argument.startswith("--preview=")
        ]
        self.assertEqual(len(previews), 1)
        result = self.run_shell(previews[0].replace("{1}", "'agent:t1'"), {"HC_STUB_READ": "out\n"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "out\n")
        self.assertEqual(self.calls(), ["hc read t1 --lines 40"])

    def test_reload_callbacks_keep_the_host_and_caller(self) -> None:
        # The popup terminal is not the caller and, run with --host app, would
        # default to the app anyway; the forwarded options keep both explicit.
        _ = self.run_pick()
        cases = [
            ("ctrl-r", ["agent:t5", "agent:t3", "agent:t4", "agent:t1", "workspace:sp2", "workspace:sp1"]),
            ("ctrl-a", ["agent:t5", "agent:t3", "agent:t4", "agent:t1"]),
            ("ctrl-w", ["workspace:sp2", "workspace:sp1"]),
        ]
        for key, targets in cases:
            with self.subTest(key=key):
                transform = self.binding(key).removeprefix("transform:")
                self.assertIn(" --host app --caller-workspace sp1 --caller-pane t1", transform)
                action = self.run_shell(transform, {"FZF_PROMPT": "> ", "HERDR_ENV": "1"}).stdout.rstrip("\n")
                reload_command = action.rpartition("reload:")[2]
                self.assertIn(" --host app --caller-workspace sp1 --caller-pane t1", reload_command)
                # HERDR_ENV=1 would default to the TUI: the forwarded --host keeps the app.
                listed = self.run_shell(reload_command, {"HERDR_ENV": "1"})
                self.assertEqual(listed.returncode, 0, listed.stderr)
                header, *rows = listed.stdout.splitlines()
                self.assertEqual(header, f"\t{PICKER_KEY_HINTS}")
                self.assertEqual(self.targets("\n".join(rows)), targets)
                self.assertEqual(self.calls(), ["herdr-app ls", "hc ls --json"])


class AppPickerTestCase(AppStubTestCase):
    """Runs the app picker's commands in a home short enough for its socket path."""

    @override
    def setUp(self) -> None:
        super().setUp()
        # macOS limits a socket path to 104 bytes; the default temporary
        # directory can be long.
        self.home = Path(tempfile.mkdtemp(dir="/tmp"))
        self.addCleanup(shutil.rmtree, self.home)
        self.env["HOME"] = str(self.home)
        self.state_directory = self.home / ".local" / "state" / "herdr-find"
        self.socket_path = self.state_directory / "app-picker.sock"

    def write_request(self, overlay: str, caller_workspace: str = "", caller_pane: str = "") -> None:
        """Record a request as show does."""
        self.state_directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        request = {"overlay": overlay, "caller_workspace": caller_workspace, "caller_pane": caller_pane}
        _ = (self.state_directory / "app-picker.json").write_text(json.dumps(request))


@final
class AppPickerServeTests(AppPickerTestCase):
    @override
    def setUp(self) -> None:
        super().setUp()
        fake_fzf = self.root / "fzf"
        _ = fake_fzf.write_text(FAKE_FZF)
        fake_fzf.chmod(0o755)
        self.fzf_argv = self.root / "fzf.argv"
        self.fzf_input = self.root / "fzf.input"
        self.env |= {
            "HERDR_FIND_FZF_PATH": str(fake_fzf),
            "FAKE_FZF_ARGV": str(self.fzf_argv),
            "FAKE_FZF_INPUT": str(self.fzf_input),
        }

    def fzf_arguments(self) -> list[str]:
        return self.fzf_argv.read_text().split("\0")[:-1]

    def serve_arguments(self) -> list[str]:
        result = self.run_cli(["serve", "--host", "app"])
        # The fake fzf exits 130, as fzf does on Esc; serve exits with fzf's status.
        self.assertEqual(result.returncode, 130, result.stderr)
        return self.fzf_arguments()

    def test_serve_listens_on_the_socket_with_picks_display(self) -> None:
        served = self.serve_arguments()
        self.assertEqual(self.fzf_input.read_text(), f"\t{PICKER_KEY_HINTS}\n")
        self.assertEqual(self.calls(), [])

        _ = self.run_cli(["pick", "--host", "app", "--caller-workspace", "sp1"])
        picked = self.fzf_arguments()
        reload_keys = ("--bind=ctrl-r:", "--bind=ctrl-a:", "--bind=ctrl-w:")
        own_options = ("--listen=", *(f"--bind={key}:" for key in ("enter", "esc", "ctrl-c", "ctrl-g", "ctrl-q")))
        self.assertEqual(
            [argument for argument in served if not argument.startswith(reload_keys + own_options)],
            [argument for argument in picked if not argument.startswith(reload_keys)],
        )
        self.assertIn(f"--listen={self.socket_path}", served)

    def test_serve_binds_enter_dismiss_and_reload_keys_to_callbacks(self) -> None:
        served = self.serve_arguments()
        self_command = shlex.quote(CLI)
        expected = [
            f"--bind=enter:transform:{self_command} accept-action {{1}}",
            *(f"--bind={key}:execute-silent:{self_command} dismiss" for key in ("esc", "ctrl-c", "ctrl-g", "ctrl-q")),
            f"--bind=ctrl-r:transform:{self_command} request-reload-action refresh",
            f"--bind=ctrl-a:transform:{self_command} request-reload-action agents",
            f"--bind=ctrl-w:transform:{self_command} request-reload-action workspaces",
            "--bind=ctrl-o:toggle-preview",
            "--bind=ctrl-u:preview-half-page-up",
            "--bind=ctrl-d:preview-half-page-down",
        ]
        self.assertEqual([argument for argument in served if argument.startswith("--bind=")], expected)

    def test_serve_keeps_the_state_directory_private(self) -> None:
        self.state_directory.mkdir(mode=0o755, parents=True)
        self.state_directory.chmod(0o755)
        _ = self.serve_arguments()
        self.assertEqual(self.state_directory.stat().st_mode & 0o777, 0o700)

    def test_serve_refuses_a_socket_path_macos_cannot_bind(self) -> None:
        long_home = self.root / ("h" * 100)
        result = self.run_cli(["serve", "--host", "app"], {"HOME": str(long_home)})
        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            result.stderr,
            f"error: socket path {long_home}/.local/state/herdr-find/app-picker.sock is longer than 104 bytes\n",
        )
        self.assertFalse(self.fzf_argv.exists())
        self.assertFalse(long_home.exists())

    def test_serve_supports_only_the_app(self) -> None:
        result = self.run_cli(["serve", "--host", "tui"])
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.fzf_argv.exists())


@final
class AppPickerCallbackTests(AppPickerTestCase):
    def test_accept_focuses_then_closes_the_recorded_popup(self) -> None:
        self.write_request("ov1", "sp1", "t1")
        result = self.run_cli(["accept-action", "agent:t5"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "change-header:\n")
        self.assertEqual(
            self.calls(),
            ['herdr-app do agent.focus {"terminal": "t5"}', 'herdr-app do overlay.close {"id": "ov1"}'],
        )

    def test_accept_selects_a_space(self) -> None:
        self.write_request("ov1")
        result = self.run_cli(["accept-action", "workspace:sp2"])
        self.assertEqual(result.stdout, "change-header:\n")
        self.assertEqual(
            self.calls(),
            ['herdr-app do space.select {"id": "sp2"}', 'herdr-app do overlay.close {"id": "ov1"}'],
        )

    def test_accept_failure_shows_the_error_and_closes_nothing(self) -> None:
        self.write_request("ov1")
        result = self.run_cli(
            ["accept-action", "agent:t5"],
            {"APP_STUB_FAIL_DO": "agent.focus", "APP_STUB_ERROR": "no terminal t5"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            """change-header:error: herdr-app do agent.focus '{"terminal": "t5"}' failed: no terminal t5\n""",
        )
        self.assertEqual(self.calls(), ['herdr-app do agent.focus {"terminal": "t5"}'])

    def test_close_without_a_request_closes_the_top_dialog(self) -> None:
        cases = [
            ("no request file", None),
            ("malformed request file", "{"),
            ("request naming no overlay", json.dumps({"overlay": "", "caller_workspace": "sp1"})),
        ]
        for name, content in cases:
            with self.subTest(name):
                request_file = self.state_directory / "app-picker.json"
                if content is not None:
                    self.state_directory.mkdir(parents=True, exist_ok=True)
                    _ = request_file.write_text(content)
                else:
                    request_file.unlink(missing_ok=True)

                result = self.run_cli(["accept-action", "agent:t5"])
                self.assertEqual(result.stdout, "change-header:\n", result.stderr)
                self.assertEqual(self.calls()[-1], "herdr-app do overlay.close {}")

                result = self.run_cli(["dismiss"])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.calls(), ["herdr-app do overlay.close {}"])

    def test_dismiss_closes_the_recorded_popup(self) -> None:
        self.write_request("ov2", "sp1")
        result = self.run_cli(["dismiss"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.calls(), ['herdr-app do overlay.close {"id": "ov2"}'])

    def test_reload_keys_use_the_recorded_caller(self) -> None:
        # The picker runs in a core terminal of its own, t8, which is never the caller.
        env = {"FZF_PROMPT": "> ", "HC_TERMINAL_ID": "t8"}
        self.write_request("ov1", "sp1", "t1")
        cases = [
            ("refresh", "reload:", ""),
            ("agents", "change-prompt(agents> )+reload:", " --only agents"),
        ]
        for key, action, only in cases:
            with self.subTest(key=key):
                result = self.run_cli(["request-reload-action", key], env)
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = f"{action}{shlex.quote(CLI)} rows --picker-header{only} --host app"
                self.assertEqual(result.stdout, f"{expected} --caller-workspace sp1 --caller-pane t1\n")
                self.assertEqual(self.calls(), [])

        self.write_request("ov2", "sp2")
        result = self.run_cli(["request-reload-action", "refresh"], env)
        self.assertTrue(result.stdout.endswith(" --host app --caller-workspace sp2\n"), result.stdout)

        (self.state_directory / "app-picker.json").unlink()
        result = self.run_cli(["request-reload-action", "refresh"], env)
        self.assertTrue(result.stdout.endswith(" rows --picker-header --host app\n"), result.stdout)
        self.assertEqual(self.calls(), [])


class FakePicker:
    """Listens on SOCKET_PATH as fzf --listen does, answering every request 200.

    Records each request's body with the request file's contents at the
    moment the request arrived.
    """

    def __init__(self, socket_path: Path, request_file: Path) -> None:
        self.request_file = request_file
        self.received: list[tuple[str, str | None]] = []
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(str(socket_path))
        self.listener.listen()
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def serve(self) -> None:
        while True:
            try:
                connection, _address = self.listener.accept()
            except OSError:
                return
            with connection:
                body = self.read_body(connection)
                recorded = self.request_file.read_text() if self.request_file.exists() else None
                self.received.append((body, recorded))
                connection.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")

    def read_body(self, connection: socket.socket) -> str:
        data = b""
        while b"\r\n\r\n" not in data:
            data += connection.recv(4096)
        head, _separator, body = data.partition(b"\r\n\r\n")
        lengths = [
            int(line.split(b":", 1)[1])
            for line in head.split(b"\r\n")
            if line.lower().startswith(b"content-length:")
        ]
        length = lengths[0] if len(lengths) > 0 else 0
        while len(body) < length:
            body += connection.recv(4096)
        return body.decode()

    def close(self) -> None:
        self.listener.close()
        self.thread.join(timeout=5)


@final
class AppPickerShowAndResetTests(AppPickerTestCase):
    def request_file(self) -> Path:
        return self.state_directory / "app-picker.json"

    def start_fake_picker(self) -> FakePicker:
        self.state_directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        picker = FakePicker(self.socket_path, self.request_file())
        self.addCleanup(picker.close)
        return picker

    def test_show_records_the_request_then_loads_its_rows(self) -> None:
        picker = self.start_fake_picker()
        self.state_directory.chmod(0o755)

        result = self.run_cli(["show", "--overlay", "ov1", "--caller-workspace", "sp1", "--caller-pane", "t1"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((result.stdout, result.stderr), ("", ""))

        recorded = {"overlay": "ov1", "caller_workspace": "sp1", "caller_pane": "t1"}
        rows_command = f"{shlex.quote(CLI)} rows --picker-header --host app --caller-workspace sp1 --caller-pane t1"
        self.assertEqual(len(picker.received), 1)
        body, request_at_post = picker.received[0]
        # The query is kept: keys typed before the rows arrive still filter them.
        self.assertEqual(body, f"change-prompt(> )+reload-sync({rows_command})+first")
        self.assertNotIn("change-query", body)
        assert request_at_post is not None
        self.assertEqual(json.loads(request_at_post), recorded)
        self.assertEqual(json.loads(self.request_file().read_text()), recorded)
        self.assertEqual(self.state_directory.stat().st_mode & 0o777, 0o700)
        # No temporary file is left beside the request file.
        state_files = sorted(path.name for path in self.state_directory.iterdir())
        self.assertEqual(state_files, ["app-picker.json", "app-picker.sock"])
        self.assertEqual(self.calls(), [])

    def test_show_without_a_pane_records_none(self) -> None:
        picker = self.start_fake_picker()
        result = self.run_cli(["show", "--overlay", "ov2", "--caller-workspace", "sp2"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(self.request_file().read_text()),
            {"overlay": "ov2", "caller_workspace": "sp2", "caller_pane": ""},
        )
        body, _request_at_post = picker.received[0]
        self.assertTrue(body.endswith(" rows --picker-header --host app --caller-workspace sp2)+first"), body)

    def test_show_fails_when_no_picker_answers(self) -> None:
        started = time.monotonic()
        result = self.run_cli(["show", "--overlay", "ov1", "--caller-workspace", "sp1"])
        elapsed = time.monotonic() - started
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertTrue(
            result.stderr.startswith(f"error: no app picker answered on {self.socket_path} within 3 s: "),
            result.stderr,
        )
        self.assertNotIn("Press enter", result.stderr)
        self.assertGreaterEqual(elapsed, 3)
        self.assertLess(elapsed, 5)

    def test_reset_asks_the_picker_to_check_the_closing_overlay(self) -> None:
        picker = self.start_fake_picker()
        result = self.run_cli(["reset", "--overlay", "ov1"])
        self.assertEqual(result.returncode, 0, result.stderr)
        bodies = [body for body, _request in picker.received]
        self.assertEqual(bodies, [f"transform:{shlex.quote(CLI)} reset-action ov1"])

    def test_reset_without_a_picker_succeeds_quickly(self) -> None:
        started = time.monotonic()
        result = self.run_cli(["reset", "--overlay", "ov1"])
        elapsed = time.monotonic() - started
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))
        self.assertLess(elapsed, 1.5)

    def test_reset_action_clears_only_for_the_recorded_or_no_overlay(self) -> None:
        clear = f"change-query()+change-prompt(> )+change-header()+reload-sync({shlex.quote(CLI)} header)\n"

        result = self.run_cli(["reset-action", "ov1"])
        self.assertEqual((result.returncode, result.stdout), (0, clear), result.stderr)

        self.write_request("ov1", "sp1")
        result = self.run_cli(["reset-action", "ov1"])
        self.assertEqual((result.returncode, result.stdout), (0, clear), result.stderr)

        # A newer show recorded ov2: the reset for ov1 changes nothing.
        self.write_request("ov2", "sp1")
        result = self.run_cli(["reset-action", "ov1"])
        self.assertEqual((result.returncode, result.stdout), (0, ""), result.stderr)
        self.assertEqual(self.calls(), [])

    def test_header_prints_the_header_line(self) -> None:
        result = self.run_cli(["header"])
        self.assertEqual((result.returncode, result.stdout), (0, f"\t{PICKER_KEY_HINTS}\n"), result.stderr)


class UnixHTTPConnection(http.client.HTTPConnection):
    """An HTTP connection to the server listening on the Unix socket at SOCKET_PATH, as fzf --listen does."""

    def __init__(self, socket_path: Path) -> None:
        super().__init__("localhost", timeout=5)
        self.socket_path = socket_path

    @override
    def connect(self) -> None:
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.settimeout(5)
        connection.connect(str(self.socket_path))
        self.sock = connection


def fzf_request(socket_path: Path, method: str, body: str | None = None) -> tuple[int, str]:
    """Send fzf's --listen server one request; return its status and body.

    A GET carries no body: fzf answers 400 to a GET with Content-Length: 0.
    """
    connection = UnixHTTPConnection(socket_path)
    try:
        connection.request(method, "/", body=body.encode() if body is not None else None)
        response = connection.getresponse()
        return response.status, response.read().decode()
    finally:
        connection.close()


@final
class AppPickerLiveTests(AppPickerTestCase):
    """Drives serve's real fzf through a pseudo-terminal and its --listen socket."""

    @override
    def setUp(self) -> None:
        super().setUp()
        try:
            master, slave = pty.openpty()
            os.close(master)
            os.close(slave)
            socket.socket(socket.AF_UNIX, socket.SOCK_STREAM).close()
        except OSError as error:
            self.skipTest(f"no pseudo-terminal or Unix socket here: {error}")

        self.env["TERM"] = "xterm-256color"
        _ = self.log.write_text("")
        self.prompt_file = self.root / "prompt"
        # serve's process and the pseudo-terminal's controlling end, once start_serve runs it.
        self.pid = 0
        self.master = -1

    def start_serve(self, env: Mapping[str, str] | None = None) -> None:
        """Run serve in a pseudo-terminal and wait for its fzf to listen."""
        serve_env = {**self.env, **(env if env is not None else {})}
        pid, self.master = pty.fork()
        if pid == 0:
            try:
                termios.tcsetwinsize(0, (40, 120))
                os.execve(CLI, [CLI, "serve", "--host", "app"], serve_env)
            finally:
                os._exit(127)
        self.pid = pid
        self.addCleanup(self.stop)
        # fzf blocks once the terminal's buffer is full, so its screen output is drained and dropped.
        threading.Thread(target=self.drain, daemon=True).start()

        self.wait_for(lambda: self.socket_path.exists() and self.state() is not None, "fzf to listen")

    def drain(self) -> None:
        try:
            while os.read(self.master, 4096) != b"":
                pass
        except OSError:
            pass

    def stop(self) -> None:
        try:
            os.killpg(self.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            _ = os.waitpid(self.pid, 0)
        except ChildProcessError:
            pass  # assert_running already reaped it.
        os.close(self.master)

    def wait_for(self, condition: Callable[[], bool], what: str, timeout: float = 10) -> None:
        deadline = time.monotonic() + timeout
        while not condition():
            if time.monotonic() > deadline:
                self.fail(f"timed out waiting for {what}; calls: {self.calls()}")
            time.sleep(0.05)

    def state(self) -> dict[str, object] | None:
        """Return fzf's state from GET, or None when it does not answer."""
        try:
            status, body = fzf_request(self.socket_path, "GET")
        except OSError:
            return None
        return cast(dict[str, object], json.loads(body)) if status == 200 else None

    def state_field(self, name: str) -> object:
        state = self.state()
        return state.get(name) if state is not None else None

    def post(self, action: str) -> None:
        status, body = fzf_request(self.socket_path, "POST", action)
        self.assertEqual(status, 200, body)

    def press(self, keys: str) -> None:
        _ = os.write(self.master, keys.encode())

    def prompt(self) -> str:
        self.prompt_file.unlink(missing_ok=True)
        self.post(f"execute-silent(printf %s \"$FZF_PROMPT\" > {shlex.quote(str(self.prompt_file))})")
        self.wait_for(self.prompt_file.exists, "the prompt")
        return self.prompt_file.read_text()

    def app_actions(self) -> list[str]:
        """Return the herdr-app do calls so far; the preview and reloads also log their calls."""
        return [call for call in self.calls() if call.startswith("herdr-app do ")]

    def assert_running(self, query: str, total_count: int) -> None:
        self.assertEqual(os.waitpid(self.pid, os.WNOHANG), (0, 0), "serve exited")
        state = self.state()
        assert state is not None
        self.assertEqual((state.get("query"), state.get("totalCount")), (query, total_count))

    def run_show(self, overlay: str) -> None:
        """Run show for OVERLAY, opened from terminal t1 of space sp1, as the popup does."""
        result = self.run_cli(["show", "--overlay", overlay, "--caller-workspace", "sp1", "--caller-pane", "t1"])
        self.assertEqual(result.returncode, 0, result.stderr)

    def run_reset(self, overlay: str) -> None:
        """Run reset for OVERLAY, as the popup does on closing, and wait until fzf has run its check."""
        result = self.run_cli(["reset", "--overlay", overlay])
        self.assertEqual((result.returncode, result.stderr), (0, ""))
        # fzf runs posted actions in order, so the prompt read runs after the reset's check.
        _ = self.prompt()

    def test_keys_run_callbacks_and_fzf_keeps_running(self) -> None:
        self.start_serve()
        self.assert_running("", 0)
        self.assertEqual(self.prompt(), "> ")

        self.post(f"reload({shlex.quote(CLI)} rows --picker-header --host app)")
        self.wait_for(lambda: self.state_field("totalCount") == 6, "rows")

        # Enter with no matching row runs no callback.
        self.press("zzz")
        self.wait_for(lambda: self.state_field("matchCount") == 0, "the query to match nothing")
        self.press("\r")
        time.sleep(0.5)
        self.assertEqual(self.app_actions(), [])
        self.assert_running("zzz", 6)
        self.post("change-query()")

        # Enter on the first row, agent t1, with no request recorded.
        self.wait_for(lambda: self.state_field("matchCount") == 6, "every row to match")
        self.press("\r")
        accepted = ['herdr-app do agent.focus {"terminal": "t1"}', "herdr-app do overlay.close {}"]
        self.wait_for(lambda: self.app_actions() == accepted, "Enter's callback")
        self.assert_running("", 6)

        self.write_request("ov1", "sp1", "t1")
        expected = list(accepted)
        for key in ("\x1b", "\x03", "\x07", "\x11"):
            with self.subTest(key=key):
                self.press(key)
                expected.append('herdr-app do overlay.close {"id": "ov1"}')
                self.wait_for(lambda: self.app_actions() == expected, f"{key!r}'s callback")
                self.assert_running("", 6)
        self.assertEqual(self.prompt(), "> ")

    def test_show_loads_rows_and_only_the_current_popups_reset_clears_them(self) -> None:
        self.start_serve()

        # Keys typed before show's rows arrive are kept.
        self.press("fix")
        self.wait_for(lambda: self.state_field("query") == "fix", "the typed query")
        self.run_show("ov1")
        self.wait_for(lambda: self.state_field("totalCount") == 6, "show's rows")
        self.assert_running("fix", 6)
        self.assertEqual(self.prompt(), "> ")

        self.post("change-prompt(agents> )")
        self.run_reset("ov0")
        self.assert_running("fix", 6)
        self.assertEqual(self.prompt(), "agents> ")

        self.run_reset("ov1")
        self.wait_for(lambda: self.state_field("totalCount") == 0, "the reset")
        self.assert_running("", 0)
        self.assertEqual(self.prompt(), "> ")

        # With no request recorded, any reset clears the picker.
        self.run_show("ov2")
        self.wait_for(lambda: self.state_field("totalCount") == 6, "show's rows")
        self.press("notes")
        self.wait_for(lambda: self.state_field("query") == "notes", "the typed query")
        (self.state_directory / "app-picker.json").unlink()
        self.run_reset("ov9")
        self.wait_for(lambda: self.state_field("totalCount") == 0, "the reset")
        self.assert_running("", 0)
        self.assertEqual(self.app_actions(), [])

    def test_enter_closes_the_popup_and_its_reset_clears_the_picker(self) -> None:
        # Closing the popup runs its closeCommand, reset, as the popup mod does.
        closing_bin = self.root / "closing-bin"
        closing_bin.mkdir()
        closing_herdr_app = closing_bin / "herdr-app"
        shared_herdr_app = shlex.quote(str(self.root / "bin" / "herdr-app"))
        _ = closing_herdr_app.write_text(CLOSING_HERDR_APP.format(shared=shared_herdr_app))
        closing_herdr_app.chmod(0o755)
        self.start_serve({"PATH": f"{closing_bin}:{self.env['PATH']}"})

        self.run_show("ov1")
        self.wait_for(lambda: self.state_field("totalCount") == 6, "show's rows")
        # An exact-match query, so only agent t5's row matches.
        self.press("'codex")
        self.wait_for(lambda: self.state_field("matchCount") == 1, "the query to match agent t5")
        self.press("\r")
        self.wait_for(lambda: self.state_field("totalCount") == 0, "the reset after Enter")
        self.assert_running("", 0)
        self.assertEqual(
            self.app_actions(),
            ['herdr-app do agent.focus {"terminal": "t5"}', 'herdr-app do overlay.close {"id": "ov1"}'],
        )


if __name__ == "__main__":
    _ = unittest.main()
