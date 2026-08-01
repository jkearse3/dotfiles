#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$("$SCRIPT_DIR/resolve-store.sh")
STORE_RELATIVE=.agent/handoffs
STORE="$ROOT/$STORE_RELATIVE"
IGNORE="$STORE/.gitignore"

slug=${1:-handoff}
slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-')
slug=${slug#-}
slug=${slug%-}
[[ -n $slug ]] || slug=handoff

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	if ! tracked_files=$(git -C "$ROOT" ls-files -- "$STORE_RELATIVE"); then
		printf '%s\n' "prepare-path: could not inspect Git tracking for $STORE_RELATIVE" >&2
		exit 1
	fi
	if [[ -n $tracked_files ]]; then
		printf '%s\n' "prepare-path: $STORE_RELATIVE must be entirely untracked" >&2
		exit 1
	fi
elif command -v jj >/dev/null 2>&1; then
	jj -R "$ROOT" status >/dev/null
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
	if [[ ! -f $IGNORE ]] || [[ $(<"$IGNORE") != '*' ]]; then
		printf '%s\n' "prepare-path: $IGNORE must contain exactly '*'" >&2
		exit 1
	fi
else
	printf '*\n' >"$IGNORE"
fi

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	! git -C "$ROOT" check-ignore -q "$STORE_RELATIVE/.gitignore"; then
	printf '%s\n' "prepare-path: $STORE_RELATIVE is not ignored" >&2
	exit 1
fi

timestamp=${HANDOFF_TIMESTAMP:-$(date '+%Y-%m-%d-%H%M%S')}
if [[ ! $timestamp =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$ ]]; then
	printf '%s\n' 'prepare-path: invalid handoff timestamp' >&2
	exit 1
fi

path="$STORE/$timestamp-$slug.md"
suffix=2

while ! (
	set -o noclobber
	: >"$path"
) 2>/dev/null; do
	path="$STORE/$timestamp-$slug-$suffix.md"
	((suffix += 1))
done

printf '%s\n' "$path"
