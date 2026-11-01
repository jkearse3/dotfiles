#!/usr/bin/env bash

# A `nix` that snapshots the Jujutsu working copy before running the real Nix.
# In a colocated jj repository, Nix reads a flake through Git and sees only
# files in the Git index, which jj updates when it snapshots the working copy.
# Running `jj util snapshot` first makes a file created since the last jj
# command visible to this Nix command.
#
# Only the repository containing the current directory is snapshotted; a flake
# reference to another repository is not inspected. The wrapper finds that
# repository as jj does, as the nearest directory at or above the current one
# that contains `.jj`, without asking jj, so a jj error inside a repository is
# never mistaken for being outside one. Outside a jj repository, or without
# `jj` on PATH, Nix runs unchanged. When the repository's `.jj` belongs to
# another user, as when nh runs Nix through sudo during `switch-system`, the
# wrapper skips the snapshot with a note on standard error and runs Nix: a
# snapshot as root would read root's jj and Git configuration, which lack the
# user's ignore rules and signing setup, and could leave root-owned files in the
# repository. When the snapshot fails for any reason, including a broken jj
# configuration, Nix does not run, so it never reads a stale working copy;
# NIX_SKIP_JJ_SNAPSHOT=1 in the user's own environment skips the snapshot.
# `package.nix` prepends REAL_NIX, the absolute path of the Nix this wrapper
# runs; it is never looked up on PATH, where it would find this wrapper again.

# Prints the jj repository root containing the current directory: the nearest
# directory at or above it that contains a `.jj` directory. Fails when no such
# directory exists.
find_jj_repository_root() {
	local directory=$PWD
	while [[ ! -d $directory/.jj ]]; do
		[[ $directory != / ]] || return 1
		directory="$(dirname "$directory")"
	done
	printf '%s\n' "$directory"
}

# Shell completion runs `nix` with NIX_GET_COMPLETIONS set on every Tab press;
# a snapshot there would print into the command line being edited and could ask
# 1Password to sign, so completions run against the last snapshot.
if [[ ${NIX_SKIP_JJ_SNAPSHOT-} != 1 && -z ${NIX_GET_COMPLETIONS-} ]] &&
	command -v jj >/dev/null 2>&1 &&
	repository_root="$(find_jj_repository_root)"; then
	if [[ ! -O $repository_root/.jj ]]; then
		echo "nix: skipped \`jj util snapshot\` because $repository_root/.jj belongs to another user; Nix may not see files created since the last jj command" >&2
	else
		# `--quiet` drops jj's status messages, such as "No snapshot needed.",
		# and anything jj still prints goes to standard error so the standard
		# output stays Nix's alone, as in `nix eval --raw … > file`.
		snapshot_status=0
		jj util snapshot --quiet >&2 || snapshot_status=$?
		if [[ $snapshot_status -ne 0 ]]; then
			echo "nix: \`jj util snapshot\` failed with status $snapshot_status in $repository_root, so Nix did not run; set NIX_SKIP_JJ_SNAPSHOT=1 to run Nix without a snapshot" >&2
			exit "$snapshot_status"
		fi
	fi
fi

exec "$REAL_NIX" "$@"
