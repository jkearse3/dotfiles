#!/usr/bin/env bash

# List branches in stack from current to default.
# Walks the first-parent chain from HEAD to the merge-base with the default
# branch, printing each branch name found along the way, then the default branch.

base=$(git-branch-default) || {
	echo "failed to get stacked branches: could not determine default branch" >&2
	exit 1
}

merge_base=$(git merge-base HEAD "$base") || {
	echo "failed to get merge base" >&2
	exit 1
}

commit_hashes=$(git rev-list --first-parent "${merge_base}..HEAD") || {
	echo "failed to list commits" >&2
	exit 1
}

if [[ -n $commit_hashes ]]; then
	while IFS= read -r hash; do
		hash="${hash#"${hash%%[![:space:]]*}"}"
		hash="${hash%"${hash##*[![:space:]]}"}"
		[[ -z $hash ]] && continue

		ref=$(git for-each-ref "--points-at=${hash}" --format='%(refname:short)' refs/heads/) || continue
		[[ -z $ref ]] && continue

		# Take only the first ref if multiple branches point at the same commit.
		echo "${ref%%$'\n'*}"
	done <<<"$commit_hashes"
fi

echo "$base"
