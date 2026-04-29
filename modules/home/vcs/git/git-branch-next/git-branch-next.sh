#!/usr/bin/env bash

# Get next branch in stack (child).
# Finds the first branch (sorted by most recent committer date) where the
# current branch is an ancestor, indicating a child relationship.

current=$(git-branch-current) || {
	echo "failed to get next branch: could not determine current branch" >&2
	exit 1
}

branch_names=$(git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads/)

if [[ -z $branch_names ]]; then
	exit 0
fi

while IFS= read -r branch; do
	branch="${branch#"${branch%%[![:space:]]*}"}"
	branch="${branch%"${branch##*[![:space:]]}"}"

	if [[ -z $branch || $branch == "$current" ]]; then
		continue
	fi

	if git merge-base --is-ancestor "$current" "$branch" 2>/dev/null; then
		echo "$branch"
		exit 0
	fi
done <<<"$branch_names"
