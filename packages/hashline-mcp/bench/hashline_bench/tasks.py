"""Editing tasks that compare hashline with Claude Code's stock file tools.

Each task is a small fixture tree, a prompt, and the exact tree the prompt
should produce, so a run is scored by byte comparison rather than judgment.
Fixtures are generated here instead of checked in, which keeps large files and
CRLF, BOM, and missing-newline cases away from the repository's formatters.
"""

import hashlib
import re
from collections.abc import Callable
from dataclasses import dataclass

type FileTree = dict[str, bytes]


@dataclass(frozen=True)
class BenchTask:
    """One benchmark case.

    `before` seeds an empty working directory. A run succeeds when the
    directory afterwards equals `after` byte for byte and, when `answer` is
    set, the session's final reply contains it as a whole word.
    """

    name: str
    prompt: str
    before: FileTree
    after: FileTree
    answer: str | None = None

    def digest(self) -> str:
        """A hash of everything that defines the task, so results recorded for
        an older version of it are never compared with new ones."""
        hasher = hashlib.sha256()
        answer = self.answer if self.answer is not None else ""
        for part in (self.name, self.prompt, answer):
            hasher.update(part.encode() + b"\0")
        for tree in (self.before, self.after):
            for path in sorted(tree):
                hasher.update(path.encode() + b"\0" + tree[path] + b"\0")
            hasher.update(b"\1")
        return hasher.hexdigest()[:16]


def bench_tasks() -> list[BenchTask]:
    """Return every task in a stable order; names are unique."""
    return [
        read_only_control(),
        one_line_in_large_file(),
        several_edits_in_one_file(),
        move_block_within_file(),
        move_block_across_files(),
        rename_across_files(),
        duplicated_block(),
        crlf_line_endings(),
        bom_without_final_newline(),
        delete_large_block(),
        move_large_block_within_file(),
        many_edits_in_large_file(),
        many_edits_across_files(),
    ]


# The tasks a run uses unless `--task` or `--all-tasks` says otherwise. The
# other tasks behave like `several-edits-in-one-file` or `crlf-line-endings`,
# a three-turn single edit, and cost a full share of each run without telling
# the arms apart; they stay available for correctness checks.
CORE_TASK_NAMES = frozenset(
    {
        "read-only-control",
        "several-edits-in-one-file",
        "crlf-line-endings",
        "move-block-within-file",
        "move-block-across-files",
        "rename-across-files",
        "delete-large-block",
        "move-large-block-within-file",
        "many-edits-in-large-file",
        "many-edits-across-files",
    }
)


# Keeps the edit instructions from inviting reformatting or cleanup, which
# would fail the byte comparison for reasons unrelated to the tools.
EXACT = "Change nothing else, and do not create any other files."


def read_only_control() -> BenchTask:
    """Answer a question without editing, to price the tool schemas alone."""
    source = handlers_module(default_multiplier)
    count = sum(1 for index in range(HANDLER_COUNT) if default_multiplier(index) == 3)
    return BenchTask(
        name="read-only-control",
        prompt=(
            "How many functions in handlers.py return `value * 3`? "
            "Reply with only the number. Do not modify any files."
        ),
        before={"handlers.py": source},
        after={"handlers.py": source},
        answer=str(count),
    )


def one_line_in_large_file() -> BenchTask:
    """Change one line whose text repeats throughout a long file."""
    target = 277

    def edited(index: int) -> int:
        return 12 if index == target else default_multiplier(index)

    return BenchTask(
        name="one-line-in-large-file",
        prompt=(
            f"In handlers.py, make handler_{target:04d} return `value * 12` "
            f"instead of its current multiplier. {EXACT}"
        ),
        before={"handlers.py": handlers_module(default_multiplier)},
        after={"handlers.py": handlers_module(edited)},
    )


HANDLER_COUNT = 400


def default_multiplier(index: int) -> int:
    return index % 9 + 1


def handlers_module(multiplier: Callable[[int], int]) -> bytes:
    """A 1,600-line module in which each `return` line recurs about 44 times."""
    blocks = [
        f"def handler_{index:04d}(value: int) -> int:\n"
        + f'    """Scale `value` for route {index}."""\n'
        + f"    return value * {multiplier(index)}\n"
        for index in range(HANDLER_COUNT)
    ]
    return "\n\n".join(blocks).encode()


def several_edits_in_one_file() -> BenchTask:
    """Make five scattered one-line changes to one file."""
    changes = {12: 5, 47: 0, 88: 999, 121: 42, 140: 7}

    def settings(overrides: dict[int, int]) -> bytes:
        lines = [
            f"OPTION_{index:03d} = {overrides.get(index, index * 10)}\n"
            for index in range(150)
        ]
        return "".join(lines).encode()

    listed = ", ".join(
        f"OPTION_{index:03d} to {value}" for index, value in changes.items()
    )
    return BenchTask(
        name="several-edits-in-one-file",
        prompt=f"In settings.py, set {listed}. {EXACT}",
        before={"settings.py": settings({})},
        after={"settings.py": settings(changes)},
    )


def move_block_within_file() -> BenchTask:
    """Move a 24-line function to another place in the same file."""
    names = [f"digest_{index:02d}" for index in range(12)]
    moved, after_name = "digest_09", "digest_02"
    reordered = [name for name in names if name != moved]
    reordered.insert(reordered.index(after_name) + 1, moved)
    return BenchTask(
        name="move-block-within-file",
        prompt=(
            f"In digests.py, move the function {moved} so it comes directly "
            f"after the function {after_name}, with the same blank-line "
            f"spacing as the other functions. {EXACT}"
        ),
        before={"digests.py": digest_module(names)},
        after={"digests.py": digest_module(reordered)},
    )


def digest_module(names: list[str]) -> bytes:
    blocks = [digest_function(name) for name in names]
    return "\n\n".join(blocks).encode()


def digest_function(name: str) -> str:
    """A distinct 24-line function; its seed comes from the name's number."""
    seed = int(name.rsplit("_", 1)[1])
    return "".join(
        [
            f"def {name}(frame: bytes) -> int:\n",
            f'    """Return the {name} checksum of `frame`."""\n',
            f"    total = {seed + 1}\n",
            "    for offset, byte in enumerate(frame):\n",
            f"        total = (total * {31 + seed} + byte + offset) % 65521\n",
            f"        if total % {seed + 3} == 0:\n",
            f"            total += {seed * 7 + 5}\n",
            f"        elif byte == {seed + 64}:\n",
            f"            total ^= {seed * 13 + 1}\n",
            "        else:\n",
            f"            total -= offset % {seed + 2}\n",
            f"    if len(frame) > {seed * 16 + 32}:\n",
            f"        total = total * {seed + 5} % 65521\n",
            "    tail = frame[-4:]\n",
            "    for index, byte in enumerate(tail):\n",
            f"        total += byte << ({seed % 4} + index)\n",
            f"    if total < {seed * 100}:\n",
            f"        total += {seed * 100}\n",
            f"    total ^= {seed * 257 + 3}\n",
            f"    total %= {65521 - seed}\n",
            f"    marker = {seed * 11} if total % 2 else {seed * 17}\n",
            "    total += marker\n",
            "    total &= 0xFFFF\n",
            "    return total\n",
        ]
    )


def move_block_across_files() -> BenchTask:
    """Move a class from one module to the end of another."""
    names = ["Account", "Invoice", "AuditEntry", "Ledger", "Payment"]
    moved = "AuditEntry"
    audit = (
        '"""Audit trail helpers."""\n'
        "\n"
        "\n"
        "def audit_label(kind: str, subject: str) -> str:\n"
        '    return f"{kind}:{subject}"\n'
    )
    kept = "\n\n".join(model_class(name) for name in names if name != moved)
    return BenchTask(
        name="move-block-across-files",
        prompt=(
            f"Move the class {moved} out of models.py and append it to the end "
            "of audit.py, separated from the code before it by two blank "
            f"lines. Leave models.py's remaining classes as they are. {EXACT}"
        ),
        before={
            "models.py": "\n\n".join(model_class(name) for name in names).encode(),
            "audit.py": audit.encode(),
        },
        after={
            "models.py": kept.encode(),
            "audit.py": (audit + "\n\n" + model_class(moved)).encode(),
        },
    )


def model_class(name: str) -> str:
    """A distinct 18-line class definition ending with a newline."""
    field = name.lower()
    return "".join(
        [
            f"class {name}:\n",
            f'    """A {field} record with its identifier and state."""\n',
            "\n",
            f"    def __init__(self, {field}_id: str, state: str) -> None:\n",
            f"        self.{field}_id = {field}_id\n",
            "        self.state = state\n",
            "        self.history: list[str] = []\n",
            "\n",
            "    def transition(self, state: str) -> None:\n",
            "        self.history.append(self.state)\n",
            "        self.state = state\n",
            "\n",
            "    def describe(self) -> str:\n",
            f'        return f"{name}({{self.{field}_id}}, {{self.state}})"\n',
            "\n",
            "    def revert(self) -> None:\n",
            "        if self.history:\n",
            "            self.state = self.history.pop()\n",
        ]
    )


def rename_across_files() -> BenchTask:
    """Rename a function across six files beside names that contain it."""
    old, new = "fetch_record", "load_record"
    before = {
        "store.py": (
            "RECORDS: dict[str, str] = {}\n"
            "\n"
            "\n"
            "def fetch_record(key: str) -> str:\n"
            "    return RECORDS[key]\n"
            "\n"
            "\n"
            "def fetch_record_count() -> int:\n"
            "    return len(RECORDS)\n"
            "\n"
            "\n"
            "def prefetch_record_cache(keys: list[str]) -> list[str]:\n"
            "    return [fetch_record(key) for key in keys]\n"
        ),
        "api.py": (
            "from store import fetch_record, fetch_record_count\n"
            "\n"
            "\n"
            "def show(key: str) -> str:\n"
            "    return fetch_record(key)\n"
            "\n"
            "\n"
            "def stats() -> str:\n"
            '    return f"{fetch_record_count()} records"\n'
        ),
        "jobs.py": (
            "from store import fetch_record, prefetch_record_cache\n"
            "\n"
            "\n"
            "def warm(keys: list[str]) -> None:\n"
            "    prefetch_record_cache(keys)\n"
            "\n"
            "\n"
            "def export(keys: list[str]) -> list[str]:\n"
            "    first = fetch_record(keys[0])\n"
            "    rest = [fetch_record(key) for key in keys[1:]]\n"
            "    return [first, *rest]\n"
        ),
        "cli.py": (
            "import sys\n"
            "\n"
            "from store import fetch_record\n"
            "\n"
            "\n"
            "def main() -> None:\n"
            "    print(fetch_record(sys.argv[1]))\n"
        ),
        "reports.py": (
            "import store\n"
            "\n"
            "\n"
            "def summary(keys: list[str]) -> str:\n"
            "    values = [store.fetch_record(key) for key in keys]\n"
            '    return ", ".join(values)\n'
        ),
        "README.md": (
            "# Records\n"
            "\n"
            "Call `fetch_record(key)` to read one record, and\n"
            "`fetch_record_count()` for the total.\n"
        ),
    }
    pattern = re.compile(rf"\b{old}\b")
    return BenchTask(
        name="rename-across-files",
        prompt=(
            f"Rename the function {old} to {new} everywhere in this directory, "
            "including its definition, imports, call sites, and documentation. "
            f"Names that merely contain {old}, such as prefetch_record_cache "
            f"and fetch_record_count, must stay unchanged. {EXACT}"
        ),
        before={path: text.encode() for path, text in before.items()},
        after={path: pattern.sub(new, text).encode() for path, text in before.items()},
    )


def duplicated_block() -> BenchTask:
    """Change one of four identical blocks, named only by its function."""
    names = ["sync_accounts", "sync_orders", "sync_invoices", "sync_payments"]
    target = "sync_invoices"

    def module(timeout_for: Callable[[str], int]) -> bytes:
        blocks = [
            f"def {name}(client: Client) -> None:\n"
            + "    for attempt in range(3):\n"
            + f"        if client.ping(timeout={timeout_for(name)}):\n"
            + "            break\n"
            + f'    client.push("{name.removeprefix("sync_")}")\n'
            for name in names
        ]
        header = "from client import Client\n\n\n"
        return (header + "\n\n".join(blocks)).encode()

    return BenchTask(
        name="duplicated-block",
        prompt=(
            f"In sync.py, change the ping timeout in {target} from 5 to 30. "
            f"The other functions keep a timeout of 5. {EXACT}"
        ),
        before={"sync.py": module(lambda _: 5)},
        after={"sync.py": module(lambda name: 30 if name == target else 5)},
    )


def crlf_line_endings() -> BenchTask:
    """Edit one line of a CRLF file; every line must keep its CRLF."""

    def ini(timeout: int) -> bytes:
        lines = ["[service]"]
        lines += [f"key_{index:02d} = value_{index:02d}" for index in range(35)]
        lines += [f"timeout_seconds = {timeout}"]
        lines += [f"key_{index:02d} = value_{index:02d}" for index in range(35, 60)]
        return "".join(f"{line}\r\n" for line in lines).encode()

    return BenchTask(
        name="crlf-line-endings",
        prompt=(
            "In legacy.ini, set timeout_seconds to 90. Keep the file's "
            f"existing line endings. {EXACT}"
        ),
        before={"legacy.ini": ini(30)},
        after={"legacy.ini": ini(90)},
    )


def bom_without_final_newline() -> BenchTask:
    """Edit a file that starts with a UTF-8 BOM and lacks a final newline."""

    def notes(status: str) -> bytes:
        lines = ["# Release notes", "", f"Status: {status}", ""]
        lines += [f"- Item {index}: adjusted component {index * 3}" for index in range(36)]
        return "﻿".encode() + "\n".join(lines).encode()

    return BenchTask(
        name="bom-without-final-newline",
        prompt=f"In notes.md, change 'Status: draft' to 'Status: final'. {EXACT}",
        before={"notes.md": notes("draft")},
        after={"notes.md": notes("final")},
    )


def delete_large_block() -> BenchTask:
    """Delete a 151-line function from the middle of a long module."""
    kept = [name for name in ROUTER_ORDER if name != LEGACY_DISPATCH]
    return BenchTask(
        name="delete-large-block",
        prompt=(
            f"Delete the function {LEGACY_DISPATCH} from router.py entirely. "
            "The functions that were around it should be separated by the same "
            f"two blank lines as the other functions. {EXACT}"
        ),
        before={"router.py": router_module(ROUTER_ORDER)},
        after={"router.py": router_module(kept)},
    )


def move_large_block_within_file() -> BenchTask:
    """Move a 151-line function about 180 lines up in the same module."""
    after_name = "route_03"
    reordered = [name for name in ROUTER_ORDER if name != LEGACY_DISPATCH]
    reordered.insert(reordered.index(after_name) + 1, LEGACY_DISPATCH)
    return BenchTask(
        name="move-large-block-within-file",
        prompt=(
            f"In router.py, move the function {LEGACY_DISPATCH} so it comes "
            f"directly after the function {after_name}, with the same "
            f"blank-line spacing as the other functions. {EXACT}"
        ),
        before={"router.py": router_module(ROUTER_ORDER)},
        after={"router.py": router_module(reordered)},
    )


LEGACY_DISPATCH = "legacy_dispatch"

# About 590 lines: forty 9-line route functions with the large function
# between the twentieth and twenty-first.
ROUTER_ORDER = [
    *(f"route_{index:02d}" for index in range(20)),
    LEGACY_DISPATCH,
    *(f"route_{index:02d}" for index in range(20, 40)),
]


def router_module(names: list[str]) -> bytes:
    blocks = [
        legacy_dispatch_function()
        if name == LEGACY_DISPATCH
        else service_function(name, int(name[-2:]), default_rate(int(name[-2:])), False)
        for name in names
    ]
    return (SERVICE_HEADER + "\n\n".join(blocks)).encode()


def legacy_dispatch_function() -> str:
    lines = [
        f"def {LEGACY_DISPATCH}(code: int) -> str:\n",
        '    """Map a legacy status code to its name."""\n',
    ]
    for index in range(74):
        keyword = "if" if index == 0 else "elif"
        lines.append(f"    {keyword} code == {1000 + index * 7}:\n")
        lines.append(f'        return "legacy-{index:03d}"\n')
    lines.append('    raise ValueError(f"unknown legacy code {code}")\n')
    return "".join(lines)


def many_edits_in_large_file() -> BenchTask:
    """Make twelve small edits across a 1,400-line module in one session."""
    prefix, count, width = "ledger", 130, 3
    rates = {7: "0.045", 33: "0.12", 58: "0.075", 81: "0.2", 104: "0.033", 126: "0.09"}
    audited = {15, 42, 66, 90, 111, 129}
    edits = sorted(
        [(index, rate_instruction(f"{prefix}_{index:0{width}d}", rate)) for index, rate in rates.items()]
        + [(index, audit_instruction(f"{prefix}_{index:0{width}d}")) for index in audited]
    )
    return BenchTask(
        name="many-edits-in-large-file",
        prompt=(
            f"Make these changes to {prefix}.py:\n"
            + "".join(f"- {text}\n" for _, text in edits)
            + EXACT
        ),
        before={f"{prefix}.py": service_module(prefix, count, width, {}, set())},
        after={f"{prefix}.py": service_module(prefix, count, width, rates, audited)},
    )


def many_edits_across_files() -> BenchTask:
    """Make sixteen small edits across eight 330-line modules in one session,
    the size of a long everyday editing session."""
    prefixes = ["billing", "orders", "inventory", "shipping", "accounts", "reports", "alerts", "search"]
    count, width = 30, 2
    before: FileTree = {}
    after: FileTree = {}
    instructions: list[str] = []
    for position, prefix in enumerate(prefixes):
        rate_index = (position * 7 + 3) % count
        audit_index = (position * 11 + 19) % count
        rate = f"0.0{position % 4 + 6}5"
        before[f"{prefix}.py"] = service_module(prefix, count, width, {}, set())
        after[f"{prefix}.py"] = service_module(
            prefix, count, width, {rate_index: rate}, {audit_index}
        )
        instructions.append(f"{prefix}.py: " + rate_instruction(f"{prefix}_{rate_index:02d}", rate))
        instructions.append(f"{prefix}.py: " + audit_instruction(f"{prefix}_{audit_index:02d}"))
    return BenchTask(
        name="many-edits-across-files",
        prompt=(
            "Make these changes in this directory:\n"
            + "".join(f"- {text}\n" for text in instructions)
            + EXACT
        ),
        before=before,
        after=after,
    )


def rate_instruction(function: str, rate: str) -> str:
    return f"In {function}, change the rate to {rate}."


def audit_instruction(function: str) -> str:
    return f'In {function}, add `audit("{function}")` as the first statement after its docstring.'


SERVICE_HEADER = "from service import Request, Response, audit\n\n\n"


def service_module(
    prefix: str,
    count: int,
    width: int,
    rates: dict[int, str],
    audited: set[int],
) -> bytes:
    """`count` 9-line service functions named `<prefix>_<index>`, with the
    rates in `rates` overriding the defaults and an `audit` call opening each
    function in `audited`. Each default rate line recurs every fifth function."""
    blocks = [
        service_function(
            f"{prefix}_{index:0{width}d}",
            index,
            rates.get(index, default_rate(index)),
            index in audited,
        )
        for index in range(count)
    ]
    return (SERVICE_HEADER + "\n\n".join(blocks)).encode()


def default_rate(seed: int) -> str:
    return f"0.0{seed % 5 + 1}"


def service_function(name: str, seed: int, rate: str, audited: bool) -> str:
    lines = [
        f"def {name}(request: Request) -> Response:\n",
        f'    """Handle the {name} step for `request`."""\n',
    ]
    if audited:
        lines.append(f'    audit("{name}")\n')
    lines += [
        f"    rate = {rate}\n",
        f"    limit = {seed % 7 * 10 + 20}\n",
        "    items = [item for item in request.items if item.weight < limit]\n",
        "    total = sum(item.price for item in items) * (1 + rate)\n",
        f"    if total > {seed * 25 + 100}:\n",
        f"        total -= {seed % 4 + 1}\n",
        f"    return Response(status={200 + seed % 3}, total=round(total, 2))\n",
    ]
    return "".join(lines)
