#!/usr/bin/env bash

# Select a registered Git worktree and print its path.

worktree_file=$(mktemp)
trap 'rm -f "$worktree_file"' EXIT

git worktree list --porcelain -z >"$worktree_file" || {
	echo "failed to list worktrees" >&2
	exit 1
}

if [[ ! -s $worktree_file ]]; then
	exit 0
fi

if ! (
	while IFS= read -r -d '' line; do
		if [[ $line == "worktree "* ]]; then
			printf '%s\0' "${line#worktree }"
		fi
	done <"$worktree_file" | fzf --read0 --print0 --prompt='Worktree: ' --select-1 --exit-0
); then
	exit 0
fi
