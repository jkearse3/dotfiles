#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

usage() {
	printf '%s\n' 'usage: prepare-ledger.sh --workspace <absolute-workspace> [slug]' >&2
	exit 2
}

# The target repository is selected explicitly and never from the caller's
# working directory. Parse and validate --workspace before any VCS inspection.
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
if [[ $workspace != /* ]]; then
	usage
fi
if [[ ! -d $workspace ]]; then
	printf '%s\n' "prepare-ledger: workspace is not a directory: $workspace" >&2
	exit 1
fi
workspace=$(cd "$workspace" && pwd -P)

# A ledger belongs to the workspace whose revisions it rewrites, so each jj
# workspace keeps its own store rather than sharing the default workspace's. jj
# discovers the workspace from a directory within it, so resolve from there.
if ! command -v jj >/dev/null 2>&1 ||
	! ROOT=$(cd "$workspace" && jj --ignore-working-copy workspace root 2>/dev/null); then
	printf '%s\n' 'prepare-ledger: not inside a jj workspace' >&2
	exit 2
fi
ROOT=$(cd "$ROOT" && pwd -P)
STORE_RELATIVE=.agent/diff-fix
STORE="$ROOT/$STORE_RELATIVE"
IGNORE="$STORE/.gitignore"

slug=${1:-ledger}
slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-')
slug=${slug#-}
slug=${slug%-}
[[ -n $slug ]] || slug=ledger
slug=${slug:0:80}
slug=${slug%-}

# Reject symlinked store components.
if [[ -L $ROOT/.agent || -L $STORE ]]; then
	printf '%s\n' "prepare-ledger: $STORE_RELATIVE must not traverse a symlink" >&2
	exit 1
fi

# Do not repurpose tracked repository content as ledger storage.
tracked_files=$(jj --ignore-working-copy -R "$ROOT" file list -- "root:$STORE_RELATIVE" 2>/dev/null) || {
	printf '%s\n' "prepare-ledger: could not inspect jj tracking for $STORE_RELATIVE" >&2
	exit 1
}
if [[ -n $tracked_files ]]; then
	printf '%s\n' "prepare-ledger: $STORE_RELATIVE must be entirely untracked" >&2
	exit 1
fi

# Require every current and future ledger to be ignored, so jj never snapshots
# one into the revisions under repair.
mkdir -p "$STORE"
if [[ -L $IGNORE ]]; then
	printf '%s\n' "prepare-ledger: $IGNORE must not be a symlink" >&2
	exit 1
elif [[ -e $IGNORE ]]; then
	if [[ ! -f $IGNORE ]] || [[ $(<"$IGNORE") != '*' ]]; then
		printf '%s\n' "prepare-ledger: $IGNORE must contain exactly '*'" >&2
		exit 1
	fi
else
	printf '*\n' >"$IGNORE"
fi

# Use a deterministic timestamp in tests and reserve a new ledger atomically.
timestamp=${LEDGER_TIMESTAMP:-$(date '+%Y-%m-%d-%H%M%S')}
if [[ ! $timestamp =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$ ]]; then
	printf '%s\n' 'prepare-ledger: invalid ledger timestamp' >&2
	exit 1
fi

suffix=2
path="$STORE/$timestamp-$slug.jsonl"

while true; do
	if [[ ! -e $path && ! -L $path ]] && (
		set -o noclobber
		: >"$path"
	) 2>/dev/null; then
		break
	fi
	if [[ ! -e $path && ! -L $path ]]; then
		printf '%s\n' "prepare-ledger: could not reserve $path" >&2
		exit 1
	fi

	path="$STORE/$timestamp-$slug--$suffix.jsonl"
	((suffix += 1))
done

printf '%s\n' "$path"
