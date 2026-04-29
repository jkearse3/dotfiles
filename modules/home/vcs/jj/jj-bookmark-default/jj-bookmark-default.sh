#!/usr/bin/env bash

# Get trunk/default bookmark name.
# Resolves the nearest bookmark matching trunk() and validates that exactly
# one result is returned. Exits 1 with all matches printed to stderr when
# multiple bookmarks match.

result=$(jj-bookmark-nearest "trunk()")

if [[ -z $result ]]; then
	echo "no trunk bookmark found" >&2
	exit 1
fi

line_count=$(echo "$result" | wc -l | tr -d ' ')

if [[ $line_count -gt 1 ]]; then
	echo "multiple trunk bookmarks found:" >&2
	echo "$result" >&2
	exit 1
fi

echo "$result"
