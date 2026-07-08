#!/usr/bin/env bash

# Get previous bookmark in stack.
# Returns the second entry from bookmark-stacked (or first if only one).
# Errors if the entry contains multiple comma-separated bookmarks.

output=$(jj-bookmark-stacked) || {
	echo "failed to get previous bookmark: could not determine stacked bookmarks" >&2
	exit 1
}

branches=()
while IFS= read -r line; do
	line="${line## }"
	line="${line%% }"
	if [[ -n $line ]]; then
		branches+=("$line")
	fi
done <<<"$output"

if [[ ${#branches[@]} -eq 0 ]]; then
	exit 0
fi

if [[ ${#branches[@]} -gt 1 ]]; then
	entry="${branches[1]}"
else
	entry="${branches[0]}"
fi

# Strip trailing * and check for comma-separated bookmarks.
entry="${entry%\*}"
if [[ $entry == *","* ]]; then
	echo "multiple bookmarks found:" >&2
	echo "$entry" | tr ',' '\n' >&2
	exit 1
fi

echo "$entry"
