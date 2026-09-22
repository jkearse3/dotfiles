#!/usr/bin/env bash

set -euo pipefail

usage() {
	printf '%s\n' 'usage: prepare-path.sh --workspace <absolute-workspace> [slug]' >&2
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

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$("$SCRIPT_DIR/resolve-workspace.sh" --workspace "$workspace")
STORE_RELATIVE=.agent/scratchpads
STORE="$ROOT/$STORE_RELATIVE"
IGNORE="$STORE/.gitignore"

slug=${1:-scratchpad}
slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-')
slug=${slug#-}
slug=${slug%-}
[[ -n $slug ]] || slug=scratchpad

for directory in "$ROOT/.agent" "$STORE"; do
	if [[ -e $directory && (! -d $directory || -L $directory) ]]; then
		printf '%s\n' "prepare-path: scratchpad path must use ordinary directories: $directory" >&2
		exit 1
	fi
done

if command -v git >/dev/null 2>&1 &&
	git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	if ! tracked_files=$(git -C "$ROOT" ls-files -- "$STORE_RELATIVE"); then
		printf '%s\n' "prepare-path: could not inspect Git tracking for $STORE_RELATIVE" >&2
		exit 1
	fi
	if [[ -n $tracked_files ]]; then
		printf '%s\n' "prepare-path: $STORE_RELATIVE must be entirely untracked" >&2
		exit 1
	fi
elif command -v jj >/dev/null 2>&1 &&
	jj --ignore-working-copy -R "$ROOT" workspace root >/dev/null 2>&1; then
	if ! tracked_files=$(jj --ignore-working-copy -R "$ROOT" file list "$STORE_RELATIVE"); then
		printf '%s\n' "prepare-path: could not inspect jj tracking for $STORE_RELATIVE" >&2
		exit 1
	fi
	if [[ -n $tracked_files ]]; then
		printf '%s\n' "prepare-path: $STORE_RELATIVE must be entirely untracked" >&2
		exit 1
	fi
fi

mkdir -p "$STORE"
if [[ -e $IGNORE ]]; then
	if [[ ! -f $IGNORE || -L $IGNORE || $(<"$IGNORE") != '*' ]]; then
		printf '%s\n' "prepare-path: $IGNORE must be a regular file containing exactly *" >&2
		exit 1
	fi
else
	printf '*\n' >"$IGNORE"
fi

if command -v git >/dev/null 2>&1 &&
	git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	if ! git -C "$ROOT" check-ignore -q "$STORE_RELATIVE/.gitignore"; then
		printf '%s\n' "prepare-path: $STORE_RELATIVE is not ignored" >&2
		exit 1
	fi
fi

timestamp=${SCRATCHPAD_TIMESTAMP:-$(date '+%Y-%m-%d-%H%M%S')}
if [[ ! $timestamp =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$ ]]; then
	printf '%s\n' 'prepare-path: invalid scratchpad timestamp' >&2
	exit 1
fi

suffix=2
path="$STORE/$timestamp-$slug.md"

while true; do
	if [[ ! -e $path && ! -L $path ]] && (
		set -o noclobber
		: >"$path"
	) 2>/dev/null; then
		break
	fi
	if [[ ! -e $path && ! -L $path ]]; then
		printf '%s\n' "prepare-path: could not reserve $path" >&2
		exit 1
	fi

	path="$STORE/$timestamp-$slug--$suffix.md"
	((suffix += 1))
done

printf '%s\n' "$path"
