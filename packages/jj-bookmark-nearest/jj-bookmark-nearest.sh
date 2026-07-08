#!/usr/bin/env bash

# Query nearest bookmarks matching a revset.
# Takes a single revset argument, outputs matching bookmark names (one per line).
# Exits 0 with no output when no bookmarks match.

if [[ $# -ne 1 ]]; then
	echo "usage: jj-bookmark-nearest <revset>" >&2
	exit 1
fi

revset="$1"

out=$(jj log --no-graph --ignore-working-copy -r "$revset" -T 'local_bookmarks.join("\n")') || {
	echo "failed to find nearest bookmark" >&2
	exit 1
}

if [[ -z $out ]]; then
	exit 0
fi

# Strip trailing * and whitespace, output each bookmark on its own line.
while IFS= read -r line; do
	line="${line%\*}"
	line="${line## }"
	line="${line%% }"
	if [[ -n $line ]]; then
		echo "$line"
	fi
done <<<"$out"
