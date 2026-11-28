"""Parse rex-agents' command line and run a subcommand for $REX_BLOCK's pane."""

from __future__ import annotations

import argparse
import contextlib
import os
import re
import sys
import tempfile
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import TextIO

from . import commands
from .clock import Clock, SystemClock
from .harness import HARNESSES, NAME_PATTERN
from .rex import CliRex, Rex, RexError
from .store import Store, StoreError
from .watch import DEFAULT_TIMEOUT, Watch

BLOCK_PATTERN = re.compile(r"block:[0-9a-f-]+")

EXIT_STATUSES = """\
exit status:
  0  success
  1  failure: Rex refused a call, state could not be read or written, or the
     request does not fit the helpers' state; the error is on stderr
  2  usage error, including $REX_BLOCK unset or not a full block ID"""

DESCRIPTION = """\
Start, watch, resume, list, and release helper agents in Rex tabs.

Each subcommand acts for the parent pane named by $REX_BLOCK. Helpers are
registered per parent under $XDG_STATE_HOME/rex-agents (~/.local/state/rex-agents
when unset), and that state is kept after helpers are released."""

START_EPILOG = f"""\
The helper's stem is <name>-<unix time>; it names the tab and the harness
session. The task gets instructions appended: write the result, or what blocks
the helper, to its result file, $TMPDIR/agent-reports/<stem>-<unix time>.md,
then end the turn, and start no agents. The tab opens with --keep-open and
--focus=false after the parent's tab and its open helpers' tabs.

output: one JSON object
  {{"name": <stem>, "harness": ..., "block": ..., "dir": ..., "result": ...}}

A stem already taken, by any parent, exits 1: choose another name.

{EXIT_STATUSES}"""

WATCH_EPILOG = f"""\
Checks the parent's helpers every 2 seconds and prints, flushed:
  <block> <stem> done                its result file is ready, or its turn
                                     ended without one
  <block> <stem> blocked [<reason>]  it waits on a prompt for the user
  <block> <stem> error [<reason>]    it reported an error
  <block> <stem> exited <code>       also `exited signal <name>` and
                                     `exited closed`
  <parent> watch-already-running     another run watches this parent; it picks
                                     up new helpers, and this run exits 0
  <parent> watch-ended               --timeout passed
  <parent> watch-failed <message>    a Rex call or the state failed; exits 1

No line repeats across runs. It exits 0 without a line once the parent has no
live helper. A tab's label gets `✓ ` on a result-file done and `✗ ` on a failed
exit without a result file.

{EXIT_STATUSES}"""

RESUME_EPILOG = f"""\
<name> is a full stem, or the <name> part when exactly one unreleased helper
has it. Refuses a helper that is starting, working, or blocked. Releases and
closes the earlier tab, then continues the same session in a new tab with a new
result file. Prints the same JSON as start.

{EXIT_STATUSES}"""

RELEASE_EPILOG = f"""\
Marks the helper released and closes its pane, ending what still runs there;
other panes in its tab stay open. Releasing a released or closed helper
succeeds. Prints nothing.

{EXIT_STATUSES}"""

LS_EPILOG = f"""\
One line per helper: stem, harness, block, state, since when, and its result
file with whether it is written. A state is one of released, exited <code |
signal <name> | closed>, working, blocked [<reason>], error [<reason>], done,
idle, or starting. Helpers without a written result file and with an open pane
also show the last 5 non-empty lines of their screen.

--json prints an array of objects with name, harness, block, state (its first
word), reason, since (ISO 8601 or null), result, result_exists, and
screen_tail (null when not shown).

{EXIT_STATUSES}"""


class UsageError(Exception):
    pass


def main(
    argv: Sequence[str] | None = None,
    *,
    env: Mapping[str, str] | None = None,
    rex: Rex | None = None,
    clock: Clock | None = None,
    stdin: TextIO | None = None,
    out: TextIO | None = None,
    err: TextIO | None = None,
) -> int:
    env = os.environ if env is None else env
    stdin = sys.stdin if stdin is None else stdin
    out = sys.stdout if out is None else out
    err = sys.stderr if err is None else err
    parser = _parser()
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            arguments = parser.parse_args(argv)
    except SystemExit as exit:
        return exit.code if isinstance(exit.code, int) else 2

    try:
        rex = CliRex() if rex is None else rex
        clock = SystemClock() if clock is None else clock
        ctx = _context(env, rex, clock, out)
        return _run(ctx, arguments, stdin, Path(os.getcwd()))
    except UsageError as error:
        _ = err.write(f"rex-agents: {error}\n")
        return 2
    except (commands.CommandError, RexError, StoreError, OSError) as error:
        _ = err.write(f"rex-agents: {error}\n")
        return 1


def _run(
    ctx: commands.Context, arguments: argparse.Namespace, stdin: TextIO, cwd: Path
) -> int:
    match arguments.command:
        case "start":
            directory = Path(os.path.abspath(cwd / (arguments.directory or ".")))
            if not directory.is_dir():
                raise UsageError(f"not a directory: {directory}")
            task = _task(arguments.task, stdin)
            commands.start(ctx, arguments.name, arguments.harness, task, directory)
        case "resume":
            commands.resume(ctx, arguments.name, _task(arguments.task, stdin))
        case "release":
            commands.release(ctx, arguments.name)
        case "ls":
            commands.ls(ctx, arguments.json)
        case "watch":
            return Watch(ctx.store, ctx.rex, ctx.clock, ctx.out).run(
                until_news=arguments.until_news, timeout=arguments.timeout
            )
    return 0


def _context(
    env: Mapping[str, str], rex: Rex, clock: Clock, out: TextIO
) -> commands.Context:
    parent = env.get("REX_BLOCK", "")
    if BLOCK_PATTERN.fullmatch(parent) is None:
        raise UsageError("REX_BLOCK must hold the parent pane's full block ID (block:<id>)")
    # An empty variable counts as unset.
    state_home = env.get("XDG_STATE_HOME", "")
    if state_home == "":
        home = env.get("HOME", "")
        state_home = os.path.join(home if home != "" else os.path.expanduser("~"), ".local", "state")
    tmp = env.get("TMPDIR", "")
    tmpdir = Path(os.path.abspath(tmp if tmp != "" else tempfile.gettempdir()))
    return commands.Context(
        parent=parent,
        store=Store(Path(state_home) / "rex-agents", parent),
        rex=rex,
        clock=clock,
        tmpdir=tmpdir,
        out=out,
    )


def _task(value: str, stdin: TextIO) -> str:
    task = stdin.read() if value == "-" else value
    if task.strip() == "":
        raise UsageError("the task is empty")
    return task


def _name(value: str) -> str:
    if NAME_PATTERN.fullmatch(value) is None:
        raise argparse.ArgumentTypeError(
            f"'{value}' must be 1 to 21 characters of a-z, 0-9, and -"
        )
    return value


def _seconds(value: str) -> int:
    if not value.isdigit():
        raise argparse.ArgumentTypeError(f"'{value}' is not a whole number of seconds")
    return int(value)


def _parser() -> argparse.ArgumentParser:
    raw = argparse.RawDescriptionHelpFormatter
    parser = argparse.ArgumentParser(
        prog="rex-agents", description=DESCRIPTION, epilog=EXIT_STATUSES, formatter_class=raw
    )
    sub = parser.add_subparsers(dest="command", required=True, metavar="<subcommand>")

    start = sub.add_parser(
        "start", help="open a helper agent in its own tab", epilog=START_EPILOG, formatter_class=raw
    )
    _ = start.add_argument("name", type=_name, help="1 to 21 characters of a-z, 0-9, and -")
    _ = start.add_argument("--harness", required=True, choices=HARNESSES)
    _ = start.add_argument("--task", required=True, help="the task, or - to read it from stdin")
    _ = start.add_argument(
        "-C", dest="directory", metavar="DIR", help="the helper's directory (default: here)"
    )

    watch = sub.add_parser(
        "watch",
        help="print one line per change in the helpers",
        epilog=WATCH_EPILOG,
        formatter_class=raw,
    )
    _ = watch.add_argument(
        "--until-news", action="store_true", help="also exit after a check that printed a line"
    )
    _ = watch.add_argument(
        "--timeout",
        type=_seconds,
        metavar="SECONDS",
        help=f"stop after SECONDS (default {DEFAULT_TIMEOUT}); 0 makes one check",
    )

    resume = sub.add_parser(
        "resume",
        help="continue a helper's session in a new tab",
        epilog=RESUME_EPILOG,
        formatter_class=raw,
    )
    _ = resume.add_argument("name", help="a full stem, or a name one unreleased helper has")
    _ = resume.add_argument("--task", required=True, help="the follow-up, or - to read it from stdin")

    release = sub.add_parser(
        "release",
        help="close a helper once its result is accepted",
        epilog=RELEASE_EPILOG,
        formatter_class=raw,
    )
    _ = release.add_argument("name", help="a full stem, a block ID, or a unique helper name")

    ls = sub.add_parser("ls", help="list the helpers and their states", epilog=LS_EPILOG, formatter_class=raw)
    _ = ls.add_argument("--json", action="store_true", help="print a JSON array")
    return parser
