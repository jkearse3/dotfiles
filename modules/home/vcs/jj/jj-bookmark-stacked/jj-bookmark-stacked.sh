#!/usr/bin/env bash

# List bookmarks from current to trunk via a single revset query.
# Uses first_ancestors(@) to follow the first-parent chain that stacked PRs
# use by convention, avoiding side-branch bookmarks that would shift indices.
# Each entry may contain multiple comma-separated bookmarks if a revision has multiple.

set -euo pipefail

trunk=$(jj-bookmark-default) || {
	echo "failed to get stacked bookmarks: could not determine trunk" >&2
	exit 1
}

# Single query: first-parent ancestors of @, within trunk..@ range (plus trunk
# itself), that carry bookmarks, excluding @. jj log outputs in topological
# order (children before parents), which is the order callers expect.
revset='first_ancestors(@) & (trunk()..@ | trunk()) & bookmarks() ~ @'
template='local_bookmarks.map(|b| b.name()).join(",") ++ "\n"'
output=$(jj log --no-graph -r "$revset" -T "$template") || {
	echo "failed to list stacked bookmarks" >&2
	exit 1
}

reached_trunk=false
while IFS= read -r name; do
	name="${name#"${name%%[![:space:]]*}"}"
	name="${name%"${name##*[![:space:]]}"}"
	[[ -z $name ]] && continue

	echo "$name"

	IFS=',' read -ra parts <<<"$name"
	for part in "${parts[@]}"; do
		if [[ $part == "$trunk" ]]; then
			reached_trunk=true
			break
		fi
	done
done <<<"$output"

# If trunk not reached (e.g., trunk has no local bookmark), append it.
if [[ $reached_trunk == false ]]; then
	echo "$trunk"
fi
