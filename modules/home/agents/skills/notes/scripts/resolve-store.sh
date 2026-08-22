#!/usr/bin/env bash

set -euo pipefail

usage() {
	printf '%s\n' 'usage: resolve-store.sh --workspace <absolute-workspace>' >&2
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
if [[ $# -gt 0 ]]; then
	usage
fi
if [[ $workspace != /* ]]; then
	usage
fi
if [[ ! -d $workspace ]]; then
	printf '%s\n' "resolve-store: workspace is not a directory: $workspace" >&2
	exit 1
fi
workspace=$(cd "$workspace" && pwd -P)

# Git lists its main worktree first. Linked worktrees therefore share the main
# checkout's local notes store instead of creating separate stores.
if command -v git >/dev/null 2>&1 && [[ $(git -C "$workspace" rev-parse --is-inside-work-tree 2>/dev/null) == true ]]; then
	while IFS= read -r -d '' field; do
		case $field in
		worktree\ *)
			printf '%s\n' "${field#worktree }"
			exit 0
			;;
		esac
	done < <(git -C "$workspace" worktree list --porcelain -z)

	printf '%s\n' 'resolve-store: Git did not report a main worktree' >&2
	exit 1
fi

if ! command -v jj >/dev/null 2>&1; then
	printf '%s\n' 'resolve-store: not inside a Git worktree or jj workspace' >&2
	exit 2
fi

if ! current_root=$(jj --ignore-working-copy -R "$workspace" workspace root 2>/dev/null); then
	printf '%s\n' 'resolve-store: not inside a Git worktree or jj workspace' >&2
	exit 2
fi

if default_root=$(jj --ignore-working-copy -R "$workspace" workspace root --name default 2>/dev/null); then
	printf '%s\n' "$default_root"
	exit 0
fi

if ! workspace_output=$(jj --ignore-working-copy -R "$workspace" workspace list -T 'name ++ "\n"' 2>/dev/null); then
	printf '%s\n' 'resolve-store: could not list jj workspaces' >&2
	exit 1
fi

workspaces=()
if [[ -n $workspace_output ]]; then
	mapfile -t workspaces <<<"$workspace_output"
fi

if [[ ${#workspaces[@]} -eq 1 ]]; then
	printf '%s\n' "$current_root"
	exit 0
fi

printf '%s\n' 'resolve-store: multiple jj workspaces exist without a default; choose a canonical workspace' >&2
exit 3
