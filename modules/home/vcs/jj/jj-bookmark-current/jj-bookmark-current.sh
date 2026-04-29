#!/usr/bin/env bash

# Get current bookmark name.
# Checks descendant bookmarks first, then ancestor bookmarks. Validates that
# exactly one result is returned. Exits 1 with all matches printed to stderr
# when multiple bookmarks match.

validate_single() {
	local result="$1"
	local direction="$2"

	if [[ -z $result ]]; then
		return 1
	fi

	local line_count
	line_count=$(echo "$result" | wc -l | tr -d ' ')

	if [[ $line_count -gt 1 ]]; then
		echo "multiple ${direction} bookmarks found:" >&2
		echo "$result" >&2
		exit 1
	fi

	echo "$result"
	exit 0
}

# Try descendant bookmark first.
result=$(jj-bookmark-nearest "roots(@:: & bookmarks())")
validate_single "$result" "descendant" || :

# Fall back to ancestor bookmark.
result=$(jj-bookmark-nearest "heads(::@ & bookmarks())")
validate_single "$result" "ancestor" || :
