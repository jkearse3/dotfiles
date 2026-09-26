"""Nix-only installation proof: the installed binary answers an MCP handshake
and edits a temporary file end to end."""

import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import IO, cast


def main() -> None:
    binary = Path(sys.argv[1]).resolve() / "bin/hashline-mcp"
    with tempfile.TemporaryDirectory() as directory:
        target = Path(directory) / "a.txt"
        _ = target.write_text("old\n")

        with subprocess.Popen(
            [binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True
        ) as server:
            assert server.stdin is not None and server.stdout is not None
            initialize = request(
                server.stdin,
                server.stdout,
                "initialize",
                {"protocolVersion": "2025-06-18"},
            )
            if dig(initialize, "result", "serverInfo", "name") != "hashline-mcp":
                raise RuntimeError(f"Unexpected initialize response: {initialize}")

            read = request(
                server.stdin,
                server.stdout,
                "tools/call",
                {"name": "read", "arguments": {"path": str(target)}},
            )
            anchor = str(dig(read, "result", "content", 0, "text")).split("│")[0]
            edit = request(
                server.stdin,
                server.stdout,
                "tools/call",
                {
                    "name": "edit",
                    "arguments": {
                        "path": str(target),
                        "edits": [{"start": f"{anchor}│old", "lines": ["new"]}],
                    },
                },
            )
            found = request(
                server.stdin,
                server.stdout,
                "tools/call",
                {"name": "grep", "arguments": {"pattern": "new", "path": str(target)}},
            )
            server.stdin.close()

        if "│new" not in str(dig(found, "result", "content", 0, "text")):
            raise RuntimeError(f"Grep failed through the wrapped PATH: {found}")
        if dig(edit, "result", "isError") is not False or target.read_text() != "new\n":
            raise RuntimeError(f"Edit failed: {edit}")


def request(
    stdin: IO[str], stdout: IO[str], method: str, params: dict[str, object]
) -> object:
    _ = stdin.write(
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
        + "\n"
    )
    stdin.flush()
    return cast(object, json.loads(stdout.readline()))


def dig(value: object, *path: str | int) -> object:
    for step in path:
        if isinstance(step, int) and isinstance(value, list):
            value = cast(list[object], value)[step]
        elif isinstance(step, str) and isinstance(value, dict):
            value = cast(dict[str, object], value)[step]
        else:
            raise RuntimeError(f"Cannot follow {step!r} into {value!r}")
    return value


if __name__ == "__main__":
    main()
