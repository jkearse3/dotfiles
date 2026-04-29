#!/usr/bin/env bash

# Interactive branch checkout using fzf.
# Lists branches and lets the user pick one, then checks it out.

out=$(git branch) || {
	echo "failed to list branches" >&2
	exit 1
}

if [[ -z $out ]]; then
	exit 0
fi

selection=$(echo "$out" | fzf) || exit 0

# Strip leading "* " marker and whitespace.
read -r first second _ <<<"$selection"
if [[ $first == "*" ]]; then
	branch="$second"
else
	branch="$first"
fi

git checkout "$branch"
