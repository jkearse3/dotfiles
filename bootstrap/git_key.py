"""Give this Mac its Secure Enclave git key for GitHub SSH and commit signing.

See docs/ssh.md, "Secure Enclave Key".

    bootstrap/git-key.sh

It creates the Secure Enclave identity labeled ``git`` when the Mac has none,
exports its handle to ``~/.ssh/git_secure_enclave``, and prints the public key,
how to add it on GitHub, and the ``GIT_SSH_COMMAND`` line that lets Nix fetch
dotfiles-private before Home Manager configures SSH. Nothing per-Mac is stored:
the identity's Common Name is its label, and the user titles the key on each
forge. A rerun reuses the identity and, when the handle
already matches it, only prints. The script never contacts GitHub.

``git-key.sh`` runs this file with the Python that this repository's
flake.lock pins, so a fresh Mac needs only Nix. It runs macOS's own
``sc_auth`` and ``ssh-keygen`` from a fixed ``PATH``. Every refusal or failure
exits 1 with one ``git-key:`` line on standard error naming the cause and the
next step. Two variables exist for its behavior test only:
GIT_KEY_TEST_STUBS, a directory put ahead of that ``PATH``, and
GIT_KEY_TEST_EXPORT_SECONDS, the export time limit.
"""

from __future__ import annotations

import os
import re
import shlex
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

LABEL = "git"
PROVIDER = "/usr/lib/ssh-keychain.dylib"
SYSTEM_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"
DEFAULT_EXPORT_SECONDS = 30.0

USAGE = """\
Usage: bootstrap/git-key.sh

Gives this Mac its Secure Enclave git key and prints what to add on GitHub.
"""


class Failure(Exception):
    """A refusal or failure, reported as one ``git-key:`` line with a next step."""


@dataclass(frozen=True)
class Identity:
    """One row of ``sc_auth list-ctk-identities``.

    ``key_hash`` is the Public Key Hash column, which holds the identity's hash,
    or, in the ``-t ssh`` listing, its SSH fingerprint.
    """

    key_hash: str
    label: str


@dataclass(frozen=True)
class KeyFiles:
    """Where the handle and its public key are installed."""

    handle: Path

    @property
    def public_key(self) -> Path:
        """The handle's public key file, ``<handle>.pub``."""
        return self.handle.with_name(f"{self.handle.name}.pub")


def main(arguments: list[str]) -> int:
    """Run the script; return its exit status."""
    stubs = os.environ.get("GIT_KEY_TEST_STUBS", "")
    os.environ["PATH"] = SYSTEM_PATH if stubs == "" else f"{stubs}:{SYSTEM_PATH}"
    export_seconds = os.environ.get("GIT_KEY_TEST_EXPORT_SECONDS", "")
    try:
        if wants_help(arguments):
            print(USAGE, end="")
            return 0
        print(
            give_key(
                KeyFiles(Path.home() / ".ssh" / "git_secure_enclave"),
                DEFAULT_EXPORT_SECONDS if export_seconds == "" else float(export_seconds),
            ),
            end="",
        )
    except Failure as failure:
        print(f"git-key: {failure}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


def wants_help(arguments: list[str]) -> bool:
    """Return whether the command line asks for help; refuse any other argument."""
    for argument in arguments:
        if argument in ("-h", "--help"):
            return True
        raise Failure(f"unknown argument {shlex.quote(argument)}; see bootstrap/git-key.sh --help")
    return False


def give_key(files: KeyFiles, export_seconds: float) -> str:
    """Create or reuse the identity, install its handle, and return the output."""
    identities = list_identities()
    if len(identities) > 1 or (len(identities) == 1 and identities[0].label != LABEL):
        raise Failure(
            f"this Mac has Secure Enclave identities other than one labeled {LABEL}, and this script "
            + 'handles only that one; list them with sc_auth list-ctk-identities and see docs/ssh.md, "Procedures"'
        )

    if len(identities) == 0:
        # Without -N, sc_auth uses the label as the Common Name.
        _ = run_or_fail(
            "cannot create the Secure Enclave identity",
            "fix what sc_auth reports, then rerun",
            ["sc_auth", "create-ctk-identity", "-l", LABEL, "-k", "p-256-ne", "-t", "none"],
        )
        identities = list_identities()
        if len(identities) != 1 or identities[0].label != LABEL:
            raise Failure(
                "created the Secure Enclave identity, but sc_auth does not list it alone; "
                + "see what sc_auth list-ctk-identities lists, then rerun"
            )

    identity = identities[0]
    fingerprints = [row.key_hash for row in list_identities("-t", "ssh") if row.label == LABEL]
    if len(fingerprints) != 1 or not fingerprints[0].startswith("SHA256:"):
        raise Failure(
            f"cannot read the SSH fingerprint of the {LABEL} identity from sc_auth list-ctk-identities -t ssh; "
            + f"delete the identity (sc_auth delete-ctk-identity -h {identity.key_hash}), {files.handle}, and "
            + f"{files.public_key}, then rerun and add the new key on GitHub"
        )
    fingerprint = fingerprints[0]

    # The os.path probes here and below answer False when they cannot look, such
    # as into a ~/.ssh this user cannot search, where Path.is_file and
    # Path.is_dir raise; the step that next touches the path then reports the
    # error in one line.
    if os.path.isfile(files.handle):
        public_key = read_public_key(files.public_key)
        if public_key is not None and fingerprint_of(files.public_key) == fingerprint:
            return output(public_key, files)

    public_key = export_and_install(identity, fingerprint, files, export_seconds)
    return output(public_key, files)


def export_and_install(identity: Identity, fingerprint: str, files: KeyFiles, export_seconds: float) -> str:
    """Export the identity's handle and install it; return its public key.

    The export runs in a private temporary directory, which is removed, and its
    result is installed only when its fingerprint is the identity's.
    """
    temporary_next_step = "set TMPDIR to a writable directory, then rerun"
    temporary_root = os.environ.get("TMPDIR", "")
    try:
        work = tempfile.TemporaryDirectory(prefix="git-key.", dir="/tmp" if temporary_root == "" else temporary_root)
    except OSError as error:
        raise Failure(f"cannot create a temporary directory ({reason(error)}); {temporary_next_step}") from None

    with work as work_name:
        export_directory = Path(work_name) / "export"
        try:
            export_directory.mkdir()
            askpass = Path(work_name) / "askpass"
            _ = askpass.write_text("#!/bin/sh\necho\n", encoding="utf-8")
            askpass.chmod(0o700)
        except OSError as error:
            raise Failure(f"cannot create a temporary directory ({reason(error)}); {temporary_next_step}") from None

        exported_handle = export_directory / "id_ecdsa_sk_rk"
        exported_public_key = export_directory / "id_ecdsa_sk_rk.pub"
        public_key = None
        if export_handle(export_directory, askpass, export_seconds) and os.path.isfile(exported_handle):
            public_key = read_public_key(exported_public_key)
        if public_key is None:
            raise Failure(
                "cannot export the key's handle; unlock the screen and rerun. If it fails with the screen "
                + f"unlocked, delete the identity (sc_auth delete-ctk-identity -h {identity.key_hash}) and rerun"
            )
        if fingerprint_of(exported_public_key) != fingerprint:
            raise Failure(
                f"the exported key does not match the {LABEL} identity ({fingerprint}); left {files.handle} "
                + f"unchanged. Delete the identity (sc_auth delete-ctk-identity -h {identity.key_hash}) and rerun"
            )
        install(exported_handle, exported_public_key, files)
    return public_key


def export_handle(directory: Path, askpass: Path, seconds: float) -> bool:
    """Run ``ssh-keygen -K`` in ``directory``; return whether it succeeded in time.

    The PIN prompt ``ssh-keygen -K`` asks first goes to ``askpass``, which
    answers an empty PIN, because ssh-keygen reads it from the terminal
    otherwise. An export still running after ``seconds`` is killed.
    """
    environment = {name: value for name, value in os.environ.items() if name != "SSH_AUTH_SOCK"}
    environment |= {"SSH_ASKPASS": str(askpass), "SSH_ASKPASS_REQUIRE": "force"}
    try:
        completed = subprocess.run(
            ["ssh-keygen", "-w", PROVIDER, "-K", "-N", ""],
            cwd=directory,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=seconds,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return completed.returncode == 0


def install(exported_handle: Path, exported_public_key: Path, files: KeyFiles) -> None:
    """Install the exported handle (mode 0600) and public key (mode 0644).

    Each is written beside its destination as ``<name>.new`` and renamed over
    it. ``~/.ssh`` is created with mode 0700 when missing.
    """
    ssh_directory = files.handle.parent
    if not os.path.isdir(ssh_directory):
        try:
            ssh_directory.mkdir(mode=0o700)
            ssh_directory.chmod(0o700)
        except OSError as error:
            raise Failure(
                f"cannot create {ssh_directory} ({reason(error)}); make {ssh_directory} a directory you can write to, then rerun"
            ) from None
    try:
        staged = [
            (stage(exported_public_key, files.public_key, 0o644), files.public_key),
            (stage(exported_handle, files.handle, 0o600), files.handle),
        ]
        for new, destination in staged:
            os.replace(new, destination)
    except OSError as error:
        raise Failure(
            f"cannot install the handle at {files.handle} ({reason(error)}); make {ssh_directory} writable, then rerun"
        ) from None


def stage(source: Path, destination: Path, mode: int) -> Path:
    """Copy ``source`` to ``<destination>.new`` with ``mode``; return that path."""
    staged = destination.with_name(f"{destination.name}.new")
    descriptor = os.open(staged, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, mode)
    with os.fdopen(descriptor, "wb") as staged_file:
        os.fchmod(staged_file.fileno(), mode)
        _ = staged_file.write(source.read_bytes())
    return staged


def list_identities(*options: str) -> list[Identity]:
    """List the Mac's Secure Enclave identities with ``sc_auth``."""
    table = run_or_fail(
        "cannot list Secure Enclave identities",
        "make sc_auth list-ctk-identities work in this terminal, then rerun",
        ["sc_auth", "list-ctk-identities", *options],
    )
    return parse_identity_table(table)


def parse_identity_table(table: str) -> list[Identity]:
    """Read the rows of ``sc_auth list-ctk-identities [-t ssh]``.

    sc_auth pads each column to its widest value and labels may contain
    spaces, so each column is cut at the offset of its header. Only the hash
    and label are read; the label ends where the Common Name column starts.
    """
    lines = table.splitlines()
    header_index = next((index for index, line in enumerate(lines) if line.startswith("Key Type")), None)
    titles = ("Public Key Hash", "Prot", "Label", "Common Name")
    offsets: list[int] = [-1] if header_index is None else [lines[header_index].find(title) for title in titles]
    if header_index is None or -1 in offsets:
        raise Failure(
            "cannot read sc_auth's identity list, which lacks its column headers; compare what "
            + "sc_auth list-ctk-identities prints with what parse_identity_table in bootstrap/git_key.py reads"
        )
    hash_at, protection_at, label_at, common_at = offsets

    identities: list[Identity] = []
    for row in lines[header_index + 1 :]:
        if row.strip() == "":
            continue
        identities.append(
            Identity(
                key_hash=row[hash_at:protection_at].strip(" "),
                label=row[label_at:common_at].strip(" "),
            )
        )
    return identities


def run_or_fail(cause: str, next_step: str, command: list[str]) -> str:
    """Run ``command`` and return its standard output.

    On failure, raise a Failure naming ``cause``, then the command's standard
    error folded into one line, then ``next_step``, so the tool's reason, such
    as an OSStatus, is kept without printing above that line.
    """
    tool = Path(command[0]).name
    try:
        completed = subprocess.run(command, capture_output=True, encoding="utf-8", errors="replace", check=False)
    except OSError as error:
        raise Failure(f"{cause} ({tool}: {reason(error)}); {next_step}") from None
    if completed.returncode == 0:
        return completed.stdout

    errors = " ".join(completed.stderr.split())
    if errors == "":
        errors = f"{tool} exited {completed.returncode}"
    elif not errors.startswith(f"{tool}: "):
        errors = f"{tool}: {errors}"
    raise Failure(f"{cause} ({errors}); {next_step}")


def fingerprint_of(public_key_file: Path) -> str | None:
    """Return the SHA256 fingerprint of an OpenSSH public key file, or None."""
    try:
        completed = subprocess.run(
            ["ssh-keygen", "-l", "-f", str(public_key_file)],
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except OSError:
        return None
    fields = completed.stdout.split()
    return fields[1] if completed.returncode == 0 and len(fields) >= 2 else None


def read_public_key(public_key_file: Path) -> str | None:
    """Return the ``<type> <key>`` fields of a public key file, or None when unreadable."""
    try:
        fields = public_key_file.read_text(encoding="utf-8").split("\n", 1)[0].split()
    except (OSError, UnicodeDecodeError):
        return None
    return " ".join(fields[:2]) if len(fields) >= 2 else None


def output(public_key: str, files: KeyFiles) -> str:
    """The success output: the key, how to add it on GitHub, and GIT_SSH_COMMAND."""
    ssh_command = (
        f"ssh -i {shlex.quote(str(files.handle))} -o IdentitiesOnly=yes -o IdentityAgent=none "
        + f"-o SecurityKeyProvider={PROVIDER}"
    )
    return f"""\
This Mac's Secure Enclave git key:

  {public_key}

Add it on GitHub at https://github.com/settings/ssh/new twice, once as an
Authentication Key and once as a Signing Key, each with a title you choose
for this Mac.

Until Home Manager configures SSH, run this in the shell used for the install:

  export GIT_SSH_COMMAND="{double_quoted_body(ssh_command)}"
"""


def double_quoted_body(text: str) -> str:
    """Escape ``text`` for use between double quotes in a POSIX shell."""
    return re.sub(r'([\\"$`])', r"\\\1", text)


def reason(error: OSError) -> str:
    """Describe a file system error as ``<path>: <reason>``."""
    text = str(error) if error.strerror is None else error.strerror
    filename: object = error.filename
    return text if filename is None else f"{filename}: {text}"


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
