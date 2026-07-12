#!/usr/bin/env python3

import argparse
import importlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol, TypedDict, cast


ENCODING = "o200k_base"


class Encoding(Protocol):
    def encode(self, text: str, *, disallowed_special: tuple[str, ...]) -> list[int]: ...


class Tiktoken(Protocol):
    def get_encoding(self, name: str) -> Encoding: ...


class Count(TypedDict):
    name: str
    count: int


@dataclass
class Args:
    json: bool
    inputs: list[str]


def parse_args() -> Args:
    parser = argparse.ArgumentParser(
        prog="token-count",
        description=(
            "Count o200k_base reference tokens in UTF-8 files or standard input. "
            "Counts exclude provider framing and other request context."
        )
    )
    _ = parser.add_argument(
        "--json",
        action="store_true",
        help="emit JSON with per-input counts and a total",
    )
    _ = parser.add_argument(
        "inputs",
        nargs="+",
        metavar="FILE",
        help="UTF-8 file to count; use - once for standard input",
    )
    namespace = parser.parse_args()
    args = Args(
        json=cast(bool, namespace.json),
        inputs=cast(list[str], namespace.inputs),
    )
    if args.inputs.count("-") > 1:
        parser.error("standard input (-) may be specified at most once")
    return args


def read_input(operand: str) -> tuple[str, str]:
    if operand == "-":
        return "stdin", sys.stdin.read()
    return operand, Path(operand).read_text(encoding="utf-8")


def main() -> int:
    args = parse_args()
    try:
        inputs = [read_input(operand) for operand in args.inputs]
    except (OSError, UnicodeError) as error:
        print(f"token-count: {error}", file=sys.stderr)
        return 1

    tiktoken = cast(Tiktoken, cast(object, importlib.import_module("tiktoken")))
    encoding = tiktoken.get_encoding(ENCODING)
    counts: list[Count] = [
        {
            "name": name,
            "count": len(encoding.encode(content, disallowed_special=())),
        }
        for name, content in inputs
    ]
    total = sum(item["count"] for item in counts)

    if args.json:
        json.dump({"encoding": ENCODING, "inputs": counts, "total": total}, sys.stdout)
        _ = sys.stdout.write("\n")
        return 0

    for item in counts:
        print(f"{item['name']}: {item['count']} reference tokens ({ENCODING})")
    if len(counts) > 1:
        print(f"total: {total} reference tokens ({ENCODING})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
