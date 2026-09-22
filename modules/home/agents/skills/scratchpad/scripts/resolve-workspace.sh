#!/usr/bin/env bash

set -euo pipefail

usage() {
	printf '%s\n' 'usage: resolve-workspace.sh --workspace <absolute-workspace>' >&2
	exit 2
}

if [[ ${1:-} != --workspace || $# -ne 2 ]]; then
	usage
fi
workspace=$2

if [[ $workspace != /* ]]; then
	usage
fi
if [[ ! -d $workspace ]]; then
	printf '%s\n' "resolve-workspace: workspace is not a directory: $workspace" >&2
	exit 1
fi
workspace=$(cd "$workspace" && pwd -P)

# Resolve the current worktree, never a repository's primary checkout. This keeps
# concurrent worktrees and jj workspaces isolated from one another.
if command -v git >/dev/null 2>&1 &&
	root=$(git -C "$workspace" rev-parse --show-toplevel 2>/dev/null); then
	(cd "$root" && pwd -P)
	exit 0
fi

if command -v jj >/dev/null 2>&1 &&
	root=$(jj --ignore-working-copy -R "$workspace" workspace root 2>/dev/null); then
	(cd "$root" && pwd -P)
	exit 0
fi

# Outside version control, the caller explicitly owns workspace-root selection.
printf '%s\n' "$workspace"
