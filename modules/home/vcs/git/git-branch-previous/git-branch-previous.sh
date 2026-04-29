#!/usr/bin/env bash

# Get previous branch in stack.
# Returns the second entry from git-branch-stacked (or first if only one).

output=$(git-branch-stacked) || {
	echo "failed to get previous branch: could not determine stacked branches" >&2
	exit 1
}

branches=()
while IFS= read -r line; do
	line="${line#"${line%%[![:space:]]*}"}"
	line="${line%"${line##*[![:space:]]}"}"
	[[ -n $line ]] && branches+=("$line")
done <<<"$output"

if [[ ${#branches[@]} -eq 0 ]]; then
	exit 0
fi

if [[ ${#branches[@]} -gt 1 ]]; then
	echo "${branches[1]}"
else
	echo "${branches[0]}"
fi
