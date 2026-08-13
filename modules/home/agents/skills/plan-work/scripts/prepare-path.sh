#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

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
STORE_RELATIVE=.agent/plans
STORE="$ROOT/$STORE_RELATIVE"
IGNORE="$STORE/.gitignore"

slug=${1:-plan}
slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-')
slug=${slug#-}
slug=${slug%-}
[[ -n $slug ]] || slug=plan
slug=${slug:0:80}
slug=${slug%-}

# Reject symlinked plan-store components.
if [[ -L $ROOT/.agent || -L $STORE ]]; then
	printf '%s\n' "prepare-path: $STORE_RELATIVE must not traverse a symlink" >&2
	exit 1
fi

# Do not repurpose tracked repository content as plan storage.
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
	if ! tracked_files=$(jj --ignore-working-copy -R "$ROOT" file list "$STORE_RELATIVE"); then
		printf '%s\n' "prepare-path: could not inspect jj tracking for $STORE_RELATIVE" >&2
		exit 1
	fi
	if [[ -n $tracked_files ]]; then
		printf '%s\n' "prepare-path: $STORE_RELATIVE must be entirely untracked" >&2
		exit 1
	fi
fi

# Require every current and future plan artifact to be ignored.
mkdir -p "$STORE"
if [[ -L $IGNORE ]]; then
	printf '%s\n' "prepare-path: $IGNORE must not be a symlink" >&2
	exit 1
elif [[ -e $IGNORE ]]; then
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

# Use a deterministic timestamp in tests and reserve a new plan atomically.
timestamp=${PLAN_TIMESTAMP:-$(date '+%Y-%m-%d-%H%M%S')}
if [[ ! $timestamp =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$ ]]; then
	printf '%s\n' 'prepare-path: invalid plan timestamp' >&2
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
