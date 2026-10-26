#!/usr/bin/env bash

set -euo pipefail

usage() {
	printf '%s\n' 'usage: prepare-run.sh --workspace <absolute-workspace> [slug]' >&2
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
STORE_RELATIVE=.agent/implement
STORE="$ROOT/$STORE_RELATIVE"
IGNORE="$STORE/.gitignore"

slug=${1:-run}
slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-')
slug=${slug#-}
slug=${slug%-}
[[ -n $slug ]] || slug=run

# The jj check reads the last recorded tree without snapshotting: the root may be
# another workspace whose working copy belongs to that workspace, and a file
# never snapshotted is not tracked. The fileset is root-relative because jj
# resolves a bare relative path against the caller's cwd rather than -R.
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	if ! tracked_files=$(git -C "$ROOT" ls-files -- "$STORE_RELATIVE"); then
		printf '%s\n' "prepare-run: could not inspect Git tracking for $STORE_RELATIVE" >&2
		exit 1
	fi
	if [[ -n $tracked_files ]]; then
		printf '%s\n' "prepare-run: $STORE_RELATIVE must be entirely untracked" >&2
		exit 1
	fi
elif command -v jj >/dev/null 2>&1; then
	if ! tracked_files=$(jj --ignore-working-copy -R "$ROOT" file list "root:\"$STORE_RELATIVE\""); then
		printf '%s\n' "prepare-run: could not inspect jj tracking for $STORE_RELATIVE" >&2
		exit 1
	fi
	if [[ -n $tracked_files ]]; then
		printf '%s\n' "prepare-run: $STORE_RELATIVE must be entirely untracked" >&2
		exit 1
	fi
fi

mkdir -p "$STORE"
# The store must ignore everything it holds. Accept any existing .gitignore whose
# every non-empty, non-comment line is '*' so run directories remain fully local;
# create a canonical single-'*' file when none exists.
if [[ -e $IGNORE ]]; then
	if [[ ! -f $IGNORE ]]; then
		printf '%s\n' "prepare-run: $IGNORE must be a regular file ignoring '*'" >&2
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
		printf '%s\n' "prepare-run: $IGNORE must ignore everything with '*'" >&2
		exit 1
	fi
else
	printf '*\n' >"$IGNORE"
fi

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	! git -C "$ROOT" check-ignore -q "$STORE_RELATIVE/.gitignore"; then
	printf '%s\n' "prepare-run: $STORE_RELATIVE is not ignored" >&2
	exit 1
fi

timestamp=${IMPLEMENT_TIMESTAMP:-$(date '+%Y-%m-%d-%H%M%S')}
if [[ ! $timestamp =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$ ]]; then
	printf '%s\n' 'prepare-run: invalid run timestamp' >&2
	exit 1
fi

# A plain mkdir reserves the run directory atomically. Only an existing name
# advances to the next suffix; any other failure, such as an unwritable store,
# would fail the same way for every suffix, so it stops with the error.
run_dir="$STORE/$timestamp-$slug"
suffix=2
until mkdir_error=$(mkdir -- "$run_dir" 2>&1); do
	if [[ ! -e $run_dir ]]; then
		printf '%s\n' "prepare-run: could not reserve $run_dir: $mkdir_error" >&2
		exit 1
	fi
	run_dir="$STORE/$timestamp-$slug-$suffix"
	((suffix += 1))
done

printf '%s\n' "$run_dir"
