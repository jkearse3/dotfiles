#!/usr/bin/env bash

set -euo pipefail

usage() {
	printf '%s\n' 'usage: prepare-path.sh --workspace <absolute-workspace> [slug]' >&2
	exit 2
}

# Parse the explicit target workspace before invoking agent-store, so malformed
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

# agent-store resolves the main checkout the workspace shares, validates the
# workspace, and prepares the untracked, fully ignored store; its non-zero
# status and stderr propagate through this substitution.
STORE=$(agent-store dir --workspace "$workspace" notes)

slug=${1:-note}
slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-')
slug=${slug#-}
slug=${slug%-}
[[ -n $slug ]] || slug=note

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
