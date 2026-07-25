#!/usr/bin/env python3

from __future__ import annotations

import argparse
import filecmp
import os
import subprocess
import sys
from pathlib import Path


OPT_IN_KEY = "direnv.worktreeAutoAllow"
GIT = os.environ.get("DIRENV_WORKTREE_GIT", "git")
DIRENV = os.environ.get("DIRENV_WORKTREE_DIRENV", "direnv")


class HookError(Exception):
    pass


def run(*arguments: str, cwd: Path | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(arguments, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def git(*arguments: str, cwd: Path | None = None) -> subprocess.CompletedProcess[bytes]:
    return run(GIT, *arguments, cwd=cwd)


def write_stderr(output: bytes) -> None:
    if output:
        _ = sys.stderr.buffer.write(output)
        _ = sys.stderr.buffer.flush()


def git_path(*arguments: str, cwd: Path | None = None, quiet: bool = False) -> Path:
    result = git(*arguments, cwd=cwd)
    if result.returncode != 0:
        if not quiet:
            write_stderr(result.stderr)
        raise HookError
    return Path(os.fsdecode(result.stdout.removesuffix(b"\n")))


def repository_root(start: Path | None = None) -> Path:
    try:
        return git_path("rev-parse", "--show-toplevel", cwd=start or Path.cwd(), quiet=True)
    except HookError:
        raise HookError("not inside a non-bare Git worktree") from None


def primary_root(checkout: Path) -> Path:
    common_dir = git_path("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=checkout)
    result = git("worktree", "list", "--porcelain", "-z", cwd=checkout)
    if result.returncode != 0:
        write_stderr(result.stderr)
        raise HookError("could not identify the primary Git worktree")
    if not result.stdout:
        raise HookError("could not identify the primary Git worktree")

    entry = result.stdout.split(b"\0", 1)[0]
    if not entry.startswith(b"worktree "):
        raise HookError("unexpected output from git worktree list --porcelain")
    primary = Path(os.fsdecode(entry.removeprefix(b"worktree ")))
    try:
        primary_common = git_path(
            "rev-parse", "--path-format=absolute", "--git-common-dir", cwd=primary, quiet=True
        )
    except (HookError, FileNotFoundError):
        raise HookError(f"primary Git worktree is unavailable: {primary}") from None
    if not common_dir.samefile(primary_common):
        raise HookError(
            f"primary Git worktree does not share the repository common directory: {primary}"
        )
    return primary


def direnv(*arguments: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        (DIRENV, *arguments), stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )


def validate_primary(primary: Path) -> None:
    if not (primary / ".envrc").is_file():
        raise HookError(f"primary worktree has no .envrc: {primary}")
    result = direnv("exec", os.fspath(primary), "true")
    if result.returncode != 0:
        raise HookError(
            f"primary worktree .envrc is not authorized and evaluable: {primary}", result.stdout
        )


def post_checkout(arguments: list[str]) -> None:
    old_head = arguments[0] if arguments else ""
    checkout_kind = arguments[2] if len(arguments) > 2 else ""
    if not old_head or old_head.strip("0") or checkout_kind != "1":
        return

    try:
        target = repository_root()
        git_dir = git_path("rev-parse", "--path-format=absolute", "--absolute-git-dir", cwd=target)
        common_dir = git_path("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=target)
    except HookError:
        return
    if git_dir.samefile(common_dir):
        return
    enabled = git("config", "--local", "--type=bool", "--get", OPT_IN_KEY, cwd=target)
    if enabled.returncode != 0 or enabled.stdout.removesuffix(b"\n") != b"true":
        return
    if not (target / ".envrc").is_file():
        return

    primary = primary_root(target)
    validate_primary(primary)
    if not filecmp.cmp(primary / ".envrc", target / ".envrc", shallow=False):
        raise HookError(f"target .envrc differs from the authorized primary worktree: {target}")

    result = direnv("allow", os.fspath(target / ".envrc"))
    if result.returncode != 0:
        raise HookError(f"could not authorize target .envrc: {target}", result.stdout)
    result = direnv("exec", os.fspath(target), "true")
    if result.returncode == 0:
        return

    revoke = direnv("deny", os.fspath(target / ".envrc"))
    extra = b""
    if revoke.returncode != 0:
        extra = os.fsencode(
            f"direnv-worktree: could not revoke the failed target authorization: {target}\n"
        )
    raise HookError(
        f"target .envrc failed evaluation after authorization: {target}",
        result.stdout + extra,
    )


def enable() -> None:
    primary = primary_root(repository_root())
    validate_primary(primary)
    result = git("config", "--local", "--type=bool", OPT_IN_KEY, "true", cwd=primary)
    if result.returncode != 0:
        write_stderr(result.stderr)
        raise HookError("could not enable repository-local worktree preparation")
    print(f"Enabled automatic direnv preparation for linked worktrees in {primary}")


def disable() -> None:
    checkout = repository_root()
    result = git("config", "--local", "--unset-all", OPT_IN_KEY, cwd=checkout)
    if result.returncode not in (0, 5):
        raise HookError("could not disable repository-local worktree preparation", result.returncode)
    print("Disabled automatic direnv preparation for this repository")


def clear_git_environment() -> None:
    result = git("rev-parse", "--local-env-vars")
    if result.returncode == 0:
        for variable in result.stdout.decode().splitlines():
            _ = os.environ.pop(variable, None)
    else:
        write_stderr(result.stderr)


def parse_arguments() -> tuple[str, list[str]]:
    parser = argparse.ArgumentParser(prog="direnv-worktree")
    subparsers = parser.add_subparsers(dest="command", required=True)
    _ = subparsers.add_parser(
        "enable", help="enable automatic direnv preparation for linked worktrees"
    )
    _ = subparsers.add_parser(
        "disable", help="disable automatic direnv preparation for linked worktrees"
    )
    post_checkout_parser = subparsers.add_parser(
        "post-checkout", help="handle Git's post-checkout hook"
    )
    _ = post_checkout_parser.add_argument("hook_arguments", nargs="*")
    _ = parser.parse_args()
    return sys.argv[1], sys.argv[2:]


def main() -> int:
    clear_git_environment()
    command, arguments = parse_arguments()
    try:
        if command == "post-checkout":
            post_checkout(arguments)
        elif command == "enable":
            enable()
        elif command == "disable":
            disable()
    except HookError as error:
        if error.args and error.args[0]:
            print(f"direnv-worktree: {error.args[0]}", file=sys.stderr, flush=True)
        if len(error.args) > 1 and isinstance(error.args[1], bytes) and error.args[1]:
            write_stderr(error.args[1])
            if not error.args[1].endswith(b"\n"):
                write_stderr(b"\n")
        return error.args[1] if len(error.args) > 1 and isinstance(error.args[1], int) else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
