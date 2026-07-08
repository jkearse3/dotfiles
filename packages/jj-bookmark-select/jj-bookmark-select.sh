#!/usr/bin/env bash

# Interactive bookmark selection using fzf.
# Lists bookmarks and lets the user pick one, outputs the bookmark name.

revset='bookmarks()'
template='coalesce(local_bookmarks) ++ "\n"'
out=$(jj log --no-graph -r "$revset" -T "$template" --color always) || {
	echo "bookmark-select command failed" >&2
	exit 1
}

if [[ -z $out ]]; then
	exit 0
fi

selection=$(echo "$out" | fzf --ansi) || exit 0

# Extract the first word (bookmark name).
read -r bookmark _ <<<"$selection"

if [[ -n $bookmark ]]; then
	echo "$bookmark"
fi
