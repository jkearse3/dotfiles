#!/usr/bin/env bash

# Interactive multi-select branch deletion using fzf.
# Lists branches, lets the user pick one or more, then deletes each.

out=$(git branch) || {
	echo "failed to list branches" >&2
	exit 1
}

if [[ -z $out ]]; then
	exit 0
fi

selection=$(echo "$out" | fzf -m) || exit 0

while IFS= read -r line; do
	read -r first second _ <<<"$line"
	if [[ $first == "*" ]]; then
		branch="$second"
	else
		branch="$first"
	fi

	if [[ -z $branch ]]; then
		continue
	fi

	if ! git branch -d "$branch"; then
		echo "warning: failed to delete branch $branch" >&2
	fi
done <<<"$selection"
