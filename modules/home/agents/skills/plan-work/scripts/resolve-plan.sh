#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

is_plan_filename() {
	[[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}-[a-z0-9]+(-[a-z0-9]+)*(--[0-9]+)?\.md$ ]]
}

usage() {
	printf '%s\n' 'usage: resolve-plan.sh --workspace <absolute-workspace> [exact-filename-or-canonical-path]' >&2
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
if [[ $# -eq 1 && $1 == -* ]]; then
	usage
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The resolver performs authoritative absolute/directory validation of the
# workspace; its non-zero status and stderr propagate through this substitution.
ROOT=$("$SCRIPT_DIR/resolve-store.sh" --workspace "$workspace")
STORE="$ROOT/.agent/plans"

# Require the canonical store layout and ignore rule created by prepare-path.sh.
if [[ -L $ROOT/.agent || -L $STORE ]]; then
	printf '%s\n' 'resolve-plan: plan store must not traverse a symlink' >&2
	exit 1
fi
if [[ (-e $ROOT/.agent && ! -d $ROOT/.agent) || (-e $STORE && ! -d $STORE) ]]; then
	printf '%s\n' "resolve-plan: plan store path must use directories: $STORE" >&2
	exit 1
fi
if [[ ! -d $STORE ]]; then
	if [[ $# -eq 0 ]]; then
		exit 0
	fi

	printf '%s\n' "resolve-plan: plan store does not exist: $STORE" >&2
	exit 1
fi
if [[ ! -f $STORE/.gitignore || $(<"$STORE/.gitignore") != '*' ]]; then
	printf '%s\n' 'resolve-plan: plan store .gitignore must contain exactly *' >&2
	exit 1
fi

# Reject stores that could expose plans through Git or jj.
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	if ! tracked_files=$(git -C "$ROOT" ls-files -- .agent/plans); then
		printf '%s\n' 'resolve-plan: could not inspect plan-store tracking' >&2
		exit 1
	fi
	if [[ -n $tracked_files ]] || ! git -C "$ROOT" check-ignore -q .agent/plans/.gitignore; then
		printf '%s\n' 'resolve-plan: plan store must be entirely ignored and untracked' >&2
		exit 1
	fi
elif command -v jj >/dev/null 2>&1; then
	if ! tracked_files=$(jj --ignore-working-copy -R "$ROOT" file list .agent/plans); then
		printf '%s\n' 'resolve-plan: could not inspect plan-store tracking' >&2
		exit 1
	fi
	if [[ -n $tracked_files ]]; then
		printf '%s\n' 'resolve-plan: plan store must be entirely untracked' >&2
		exit 1
	fi
fi

if [[ $# -eq 0 ]]; then
	shopt -s nullglob
	for candidate in "$STORE"/*.md; do
		[[ -f $candidate && ! -L $candidate ]] || continue
		is_plan_filename "${candidate##*/}" || continue
		printf '%s\n' "$candidate"
	done
	exit 0
fi

identifier=$1

# Explicit paths are accepted only when absolute and their physical parent is
# the plan store. Relative explicit paths are never resolved against the cwd.
if [[ $identifier == */* ]]; then
	if [[ $identifier != /* ]]; then
		printf '%s\n' "resolve-plan: explicit plan path must be absolute: $identifier" >&2
		exit 2
	fi
	candidate=$identifier

	candidate_parent=$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P) || {
		printf '%s\n' "resolve-plan: plan path does not exist: $identifier" >&2
		exit 1
	}
	store_physical=$(cd "$STORE" && pwd -P)
	candidate="$candidate_parent/$(basename "$candidate")"

	if [[ $candidate_parent != "$store_physical" ]]; then
		printf '%s\n' 'resolve-plan: explicit plan path is outside the canonical store' >&2
		exit 2
	fi
	if ! is_plan_filename "$(basename "$candidate")"; then
		printf '%s\n' "resolve-plan: invalid plan filename: $identifier" >&2
		exit 2
	fi
	if [[ ! -f $candidate || -L $candidate ]]; then
		printf '%s\n' "resolve-plan: plan is not a regular non-symlink file: $identifier" >&2
		exit 1
	fi

	printf '%s\n' "$candidate"
	exit 0
fi

if ! is_plan_filename "$identifier"; then
	printf '%s\n' "resolve-plan: invalid exact plan filename: $identifier" >&2
	exit 2
fi

candidate=$STORE/$identifier
if [[ ! -f $candidate || -L $candidate ]]; then
	printf '%s\n' "resolve-plan: plan is not a regular non-symlink file: $identifier" >&2
	exit 1
fi

printf '%s\n' "$candidate"
