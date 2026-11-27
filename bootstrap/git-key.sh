#!/bin/bash

# Gives this Mac its Secure Enclave git key for GitHub SSH and commit signing.
#
#   bootstrap/git-key.sh
#
# git_key.py beside this script does the work and documents it. This wrapper
# runs it with the python3 of the nixpkgs that this repository's flake.lock
# pins, so a fresh Mac needs only Nix. `--inputs-from` reads only that lock:
# Nix fetches nixpkgs but not dotfiles-private, which needs the key this
# script creates. The script reads only flake.lock and git_key.py from the
# checkout, so NIX_SKIP_JJ_SNAPSHOT=1 keeps this repository's `nix` wrapper
# from snapshotting the jj working copy first, which fails while jj cannot
# sign, and `warn-dirty false` drops Nix's note that the Git tree has
# uncommitted changes, which a jj working copy usually has.

repository=$(cd "$(dirname "$0")/.." && pwd) || exit 1
if ! command -v nix >/dev/null 2>&1; then
	echo 'git-key: Nix is not on PATH; install it as docs/installation.md, "Install Bootstrap Tools", describes, open a new terminal, then rerun' >&2
	exit 1
fi
NIX_SKIP_JJ_SNAPSHOT=1 exec nix run --option warn-dirty false --inputs-from "$repository" nixpkgs#python3 -- \
	-I "$repository/bootstrap/git_key.py" "$@"
