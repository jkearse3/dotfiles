#!/usr/bin/env bash

set -euo pipefail

usage() {
	printf '%s\n' 'usage: prepare-run.sh --workspace <absolute-workspace> [slug]' >&2
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
STORE=$(agent-store dir --workspace "$workspace" implement)

slug=${1:-run}
slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-')
slug=${slug#-}
slug=${slug%-}
[[ -n $slug ]] || slug=run

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
