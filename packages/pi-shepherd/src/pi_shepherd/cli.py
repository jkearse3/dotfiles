"""One human/JSON command grammar; result acknowledgement follows successful output."""

# argparse registration and stream writes intentionally discard library return values.
# pyright: reportUnusedCallResult=false

import argparse
import json
import os
import sqlite3
import sys
from collections.abc import Callable, Mapping, Sequence
from importlib.resources import files
from pathlib import Path
from typing import cast

from . import messages, terminal
from .config import load_config
from .errors import TeamError, present
from .herdr import Herdr
from .locks import Locks
from .models import READ_SOURCES, STATUSES, Request
from .private_fs import lock_root, registry_path
from .registry import Registry
from .teammates import Team


class Arguments(argparse.Namespace):
    command: str = ""
    json: bool = False
    skill: bool = False
    name: str = ""
    ref: str = ""
    request_id: str = ""
    profile: str | None = None
    cwd: str | None = None
    startup_timeout: int | None = None
    timeout: int | None = None
    all: bool = False
    include_closed: bool = False
    force: bool = False
    apply: bool = False
    until: str | None = None
    source: str | None = None
    lines: int | None = None
    ansi: bool = False
    prompt: str | None = None
    prompt_file: str | None = None
    wait: bool = False
    allow_focused: bool = False
    stdin: bool = False
    file: str = ""
    ack: bool = False


def integer(minimum: int, maximum: int) -> Callable[[str], int]:
    def parse(value: str) -> int:
        try:
            result = int(value)
        except ValueError as error:
            raise argparse.ArgumentTypeError("Expected an integer") from error
        if not minimum <= result <= maximum:
            raise argparse.ArgumentTypeError(f"Expected {minimum}..{maximum}")
        return result

    return parse


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(
        prog="pi-shepherd",
        description="Persistent Pi teammates in Herdr workspaces",
    )
    root.add_argument("--json", action="store_true")
    root.add_argument("--skill", action="store_true")
    commands = root.add_subparsers(dest="command")
    commands.add_parser("profiles", help="list configured static profiles")
    create = commands.add_parser("create", help="create a no-focus teammate tab")
    create.add_argument("name")
    create.add_argument("--profile")
    create.add_argument("--cwd")
    create.add_argument("--startup-timeout", type=integer(4, 300))
    listing = commands.add_parser("list", help="list workspace teammates")
    listing.add_argument("--all", action="store_true")
    listing.add_argument("--include-closed", action="store_true")
    for name in (
        "show",
        "focus",
        "attach",
        "repair",
        "close",
        "forget",
        "wait",
        "read",
        "request",
    ):
        command = commands.add_parser(name)
        command.add_argument("ref")
        if name in ("close", "forget"):
            command.add_argument("--force", action="store_true")
        if name == "repair":
            command.add_argument("--apply", action="store_true")
        if name in ("wait", "request"):
            command.add_argument("--timeout", type=integer(0, 86400))
        if name == "wait":
            command.add_argument("--until", choices=STATUSES)
        if name == "read":
            command.add_argument("--source", choices=READ_SOURCES)
            command.add_argument("--lines", type=integer(1, 10000))
            command.add_argument("--ansi", action="store_true")
        if name == "request":
            source = command.add_mutually_exclusive_group(required=True)
            source.add_argument("--stdin", action="store_true")
            source.add_argument("--prompt")
            source.add_argument("--prompt-file")
            command.add_argument("--wait", action="store_true")
            command.add_argument("--allow-focused", action="store_true")
    for name in ("reply", "result", "cancel"):
        command = commands.add_parser(name)
        command.add_argument("request_id")
        if name == "reply":
            source = command.add_mutually_exclusive_group(required=True)
            source.add_argument("--stdin", action="store_true")
            source.add_argument("--file")
        if name == "result":
            command.add_argument("--wait", action="store_true")
            command.add_argument("--timeout", type=integer(0, 86400))
            command.add_argument("--ack", action="store_true")
    return root


def parse_args(argv: Sequence[str]) -> Arguments:
    root = parser()
    args = root.parse_args(argv, namespace=Arguments())
    if args.skill:
        if list(argv) != ["--skill"]:
            root.error("--skill is exclusive")
    elif not args.command:
        root.error("a command is required")
    if args.command == "attach" and args.json:
        root.error("attach is interactive and rejects --json")
    return args


def emit(command: str, result: object, json_mode: bool) -> None:
    if (
        not json_mode
        and isinstance(result, dict)
        and command in ("read", "request", "result")
        and cast(Mapping[str, object], result).get("content") is not None
    ):
        sys.stdout.write(str(cast(Mapping[str, object], result)["content"]))
    else:
        payload: object = (
            {
                "schema_version": 2,
                "ok": True,
                "command": command,
                "result": cast(object, result),
            }
            if json_mode
            else cast(object, result)
        )
        print(
            json.dumps(
                payload,
                ensure_ascii=False,
                sort_keys=True,
                indent=None if json_mode else 2,
            )
        )
    sys.stdout.flush()


def dispatch(team: Team, args: Arguments) -> object:
    timeout = args.timeout
    timeout = team.config.wait_timeout_seconds if timeout is None else timeout
    if args.command == "create":
        return team.create(args.name, args.profile, args.cwd, args.startup_timeout)
    if args.command == "list":
        return team.list(args.all, args.include_closed)
    if args.command == "show":
        return team.show(args.ref)
    if args.command == "repair":
        return team.repair(args.ref, args.apply)
    if args.command == "close":
        return team.close(args.ref, args.force)
    if args.command == "forget":
        return team.forget(args.ref, args.force)
    if args.command == "focus":
        return terminal.focus(team, args.ref)
    if args.command == "read":
        return terminal.read(
            team,
            args.ref,
            args.source or team.config.read_source,
            args.lines or team.config.read_lines,
            args.ansi,
        )
    if args.command == "wait":
        return terminal.wait(team, args.ref, args.until, timeout)
    if args.command == "reply":
        if args.stdin:
            body = messages.read_body(sys.stdin.buffer)
        else:
            with Path(args.file).open("rb") as stream:
                body = messages.read_body(stream)
        return messages.reply(team, args.request_id, body)
    if args.command == "request":
        text = sys.stdin.read() if args.stdin else args.prompt
        if args.prompt_file is not None:
            text = (
                sys.stdin.read()
                if args.prompt_file == "-"
                else Path(args.prompt_file).read_text(encoding="utf-8")
            )
        return messages.request(
            team, args.ref, present(text), args.wait, timeout, args.allow_focused
        )
    raise TeamError("usage", "Unsupported command")


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if args.skill:
        sys.stdout.write(
            files("pi_shepherd").joinpath("SKILL.md").read_text(encoding="utf-8")
        )
        return 0
    os.umask(0o077)
    registry: Registry | None = None
    acknowledgement: Request | None = None
    emitted = False
    try:
        config = load_config()
        if args.command == "profiles":
            result: object = [
                {
                    "name": profile.name,
                    "selection_hint": profile.selection_hint,
                }
                for _, profile in sorted(config.profiles.items())
            ]
        else:
            registry = Registry(registry_path())
            if args.command == "result":
                timeout = (
                    config.wait_timeout_seconds
                    if args.timeout is None
                    else args.timeout
                )
                request = messages.result(registry, args.request_id, args.wait, timeout)
                result = messages.result_view(request)
                if args.wait:
                    result["wait_outcome"] = (
                        "completed" if request.reply is not None else "timeout"
                    )
                if args.ack and request.reply is not None:
                    acknowledgement = request
            elif args.command == "cancel":
                registry.request(args.request_id)
                registry.cancel(args.request_id)
                result = {"request_id": args.request_id, "cancelled": True}
            else:
                team = Team(registry, Herdr(), Locks(lock_root()), config)
                if args.command == "attach":
                    return terminal.attach(team, args.ref)
                result = dispatch(team, args)
        if args.command == "forget" and args.force:
            print(
                "WARNING: forced forget may orphan a live tab or discard a result",
                file=sys.stderr,
            )
        emit(args.command, result, args.json)
        emitted = True
        if acknowledgement is not None and registry is not None:
            registry.acknowledge(acknowledgement)
        return 0
    except (TeamError, OSError, UnicodeError, sqlite3.Error) as error:
        failure = (
            error
            if isinstance(error, TeamError)
            else TeamError("local_error", "Local I/O or state operation failed")
        )
        payload = {
            "schema_version": 2,
            "ok": False,
            "command": args.command,
            "error": {
                "code": failure.code,
                "message": failure.message,
                "uncertain": failure.uncertain,
            },
        }
        try:
            if args.json and not emitted and not isinstance(error, BrokenPipeError):
                print(json.dumps(payload, sort_keys=True))
                sys.stdout.flush()
            else:
                print(f"{failure.code}: {failure.message}", file=sys.stderr)
        except OSError:
            pass
        return 1
    finally:
        if registry is not None:
            registry.close()
