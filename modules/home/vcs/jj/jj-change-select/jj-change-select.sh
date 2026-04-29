#!/usr/bin/env bash

# Interactive change selection using fzf.
# Lists jj log entries and lets the user pick one, outputs the change ID.

template='change_id.shortest() ++ "\t" ++ description.first_line() ++ " " ++ bookmarks.join("  ") ++ "\n"'
out=$(jj log --no-graph -T "$template" --color always) || {
	echo "select command failed" >&2
	exit 1
}

if [[ -z $out ]]; then
	exit 0
fi

selection=$(echo "$out" | fzf --ansi) || exit 0

# Extract the change ID (first tab-separated field).
change_id="${selection%%	*}"
change_id="${change_id## }"
change_id="${change_id%% }"

if [[ -n $change_id ]]; then
	echo "$change_id"
fi
