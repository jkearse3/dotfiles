#!/usr/bin/env bash

set -euo pipefail

if command -v git >/dev/null 2>&1 && [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) == true ]]; then
	while IFS= read -r -d '' field; do
		case $field in
		worktree\ *)
			printf '%s\n' "${field#worktree }"
			exit 0
			;;
		esac
	done < <(git worktree list --porcelain -z)

	printf '%s\n' 'resolve-store: Git did not report a main worktree' >&2
	exit 1
fi

if ! command -v jj >/dev/null 2>&1; then
	printf '%s\n' 'resolve-store: not inside a Git worktree or jj workspace' >&2
	exit 2
fi

if ! current_root=$(jj --ignore-working-copy workspace root 2>/dev/null); then
	printf '%s\n' 'resolve-store: not inside a Git worktree or jj workspace' >&2
	exit 2
fi

if default_root=$(jj --ignore-working-copy workspace root --name default 2>/dev/null); then
	printf '%s\n' "$default_root"
	exit 0
fi

if ! workspace_output=$(jj --ignore-working-copy workspace list -T 'name ++ "\n"' 2>/dev/null); then
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
