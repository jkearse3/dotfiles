"""Nix-only installation proof, with no source-tree imports or runtime contact."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import cast


def main() -> None:
    output = Path(sys.argv[1]).resolve()
    binary = output / "bin/pi-shepherd"
    candidates = list(output.glob("lib/python*/site-packages/pi_shepherd/__init__.py"))
    if len(candidates) != 1:
        raise RuntimeError("Installed module location is absent or ambiguous")
    package_root = candidates[0].parent.parent
    with tempfile.TemporaryDirectory() as directory:
        environment = {
            "HOME": directory,
            "PATH": os.environ["PATH"],
            "PYTHONPATH": str(package_root),
            "XDG_CONFIG_HOME": directory + "/config",
            "XDG_STATE_HOME": directory + "/state",
        }

        def run(arguments: list[str]) -> bytes:
            return subprocess.run(
                arguments,
                cwd=directory,
                env=environment,
                check=True,
                capture_output=True,
            ).stdout

        imported = run(
            [
                sys.executable,
                "-B",
                "-c",
                "import pi_shepherd; print(pi_shepherd.__file__)",
            ]
        )
        if not Path(imported.decode().strip()).is_relative_to(output):
            raise RuntimeError("Module did not import from the installed store output")
        _ = run(
            [
                sys.executable,
                "-B",
                "-c",
                "from pi_shepherd.herdr import Herdr; Herdr().compatibility()",
            ]
        )
        packaged_skill = (output / "share/pi-shepherd/SKILL.md").read_bytes()
        if run([str(binary), "--skill"]) != packaged_skill:
            raise RuntimeError("Packaged skill does not match CLI skill output")
        for command in ([str(binary)], [sys.executable, "-B", "-m", "pi_shepherd"]):
            result = cast(
                dict[str, object], json.loads(run([*command, "--json", "profiles"]))
            )
            if result != {
                "schema_version": 2,
                "ok": True,
                "command": "profiles",
                "result": [],
            }:
                raise RuntimeError("Installed nonmutating JSON contract failed")
        if Path(environment["XDG_STATE_HOME"]).exists():
            raise RuntimeError("Informational commands created persistent state")


if __name__ == "__main__":
    main()
