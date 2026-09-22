#!/usr/bin/env bash

set -euo pipefail

usage() {
	printf '%s\n' 'usage: resolve-scratchpad.sh --workspace <absolute-workspace> [exact-filename-or-path]' >&2
	exit 2
}

if [[ ${1:-} != --workspace || $# -lt 2 ]]; then
	usage
fi
workspace=$2
shift 2
if [[ $# -gt 1 ]]; then
	usage
fi
identifier=${1:-}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$("$SCRIPT_DIR/resolve-workspace.sh" --workspace "$workspace")
STORE_RELATIVE=.agent/scratchpads
STORE="$ROOT/$STORE_RELATIVE"

if [[ ! -d $STORE || -L $ROOT/.agent || -L $STORE ]]; then
	printf '%s\n' "resolve-scratchpad: safe scratchpad store does not exist: $STORE" >&2
	exit 1
fi
if [[ ! -f $STORE/.gitignore || -L $STORE/.gitignore || $(<"$STORE/.gitignore") != '*' ]]; then
	printf '%s\n' 'resolve-scratchpad: scratchpad store .gitignore must contain exactly *' >&2
	exit 1
fi

if command -v git >/dev/null 2>&1 &&
	git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	if ! tracked_files=$(git -C "$ROOT" ls-files -- "$STORE_RELATIVE"); then
		printf '%s\n' 'resolve-scratchpad: could not inspect Git tracking' >&2
		exit 1
	fi
	if [[ -n $tracked_files ]] || ! git -C "$ROOT" check-ignore -q "$STORE_RELATIVE/.gitignore"; then
		printf '%s\n' 'resolve-scratchpad: scratchpad store must be entirely ignored and untracked' >&2
		exit 1
	fi
elif command -v jj >/dev/null 2>&1 &&
	jj --ignore-working-copy -R "$ROOT" workspace root >/dev/null 2>&1; then
	if ! tracked_files=$(jj --ignore-working-copy -R "$ROOT" file list "$STORE_RELATIVE"); then
		printf '%s\n' 'resolve-scratchpad: could not inspect jj tracking' >&2
		exit 1
	fi
	if [[ -n $tracked_files ]]; then
		printf '%s\n' 'resolve-scratchpad: scratchpad store must be entirely ignored and untracked' >&2
		exit 1
	fi
fi

if [[ -z $identifier ]]; then
	find "$STORE" -maxdepth 1 -type f ! -name .gitignore \
		-name '????-??-??-??????-*.md' -print | LC_ALL=C sort
	exit 0
fi

if [[ $identifier == /* ]]; then
	candidate=$identifier
else
	if [[ $identifier == */* ]]; then
		usage
	fi
	candidate="$STORE/$identifier"
fi

candidate_directory=$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P) || {
	printf '%s\n' "resolve-scratchpad: scratchpad does not exist: $candidate" >&2
	exit 1
}
if [[ $candidate_directory != "$STORE" || ! -f $candidate || -L $candidate ]]; then
	printf '%s\n' "resolve-scratchpad: not a regular scratchpad in $STORE: $identifier" >&2
	exit 1
fi
if [[ $(basename "$candidate") != ????-??-??-??????-*.md ]]; then
	printf '%s\n' "resolve-scratchpad: invalid scratchpad filename: $(basename "$candidate")" >&2
	exit 1
fi

printf '%s\n' "$candidate"
