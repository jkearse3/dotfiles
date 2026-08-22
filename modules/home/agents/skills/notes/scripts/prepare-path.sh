#!/usr/bin/env bash

set -euo pipefail

usage() {
	printf '%s\n' 'usage: prepare-path.sh --workspace <absolute-workspace> [slug]' >&2
	exit 2
}

# Parse the explicit target workspace before invoking the resolver, so malformed
# CLI input fails with a usage error rather than reaching repository discovery.
if [[ ${1:-} != --workspace ]]; then
	usage
fi
if [[ $# -lt 2 ]]; then
	usage
fi
workspace=$2
shift 2
if [[ $# -gt 1 ]]; then
	usage
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The resolver performs authoritative absolute/directory validation of the
# workspace; its non-zero status and stderr propagate through this substitution.
ROOT=$("$SCRIPT_DIR/resolve-store.sh" --workspace "$workspace")
STORE_RELATIVE=.agent/notes
STORE="$ROOT/$STORE_RELATIVE"
IGNORE="$STORE/.gitignore"

slug=${1:-note}
slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-')
slug=${slug#-}
slug=${slug%-}
[[ -n $slug ]] || slug=note

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
# The store must ignore everything it holds. Accept any existing .gitignore whose
# every non-empty, non-comment line is '*' so notes remain fully local; create a
# canonical single-'*' file when none exists.
if [[ -e $IGNORE ]]; then
	if [[ ! -f $IGNORE ]]; then
		printf '%s\n' "prepare-path: $IGNORE must be a regular file ignoring '*'" >&2
		exit 1
	fi
	ignore_ok=0
	while IFS= read -r line || [[ -n $line ]]; do
		[[ -z $line || $line == \#* ]] && continue
		if [[ $line == '*' ]]; then
			ignore_ok=1
		else
			ignore_ok=0
			break
		fi
	done <"$IGNORE"
	if [[ $ignore_ok -ne 1 ]]; then
		printf '%s\n' "prepare-path: $IGNORE must ignore everything with '*'" >&2
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

timestamp=${NOTES_TIMESTAMP:-$(date '+%Y-%m-%d-%H%M%S')}
if [[ ! $timestamp =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$ ]]; then
	printf '%s\n' 'prepare-path: invalid note timestamp' >&2
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
