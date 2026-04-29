#!/usr/bin/env bash

# Build a jj status line for the starship prompt.
# Outputs ANSI-colored segments: bookmark, distance arrow, change ID, conflict, modification.

# ANSI color codes.
COLOR_RESET=$'\033[0m'
COLOR_BOLD_PURPLE=$'\033[1;35m'
COLOR_CYAN=$'\033[0;36m'
COLOR_BOLD_RED=$'\033[1;31m'
COLOR_BOLD_YELLOW=$'\033[1;33m'

# Format the first bookmark with a (+Nb) suffix when additional bookmarks match.
# Input: multi-line bookmark list from jj-bookmark-nearest.
# Outputs: "first_bookmark(+Nb)" or "first_bookmark" if only one.
format_bookmark() {
	local lines="$1"
	local bookmark extra
	bookmark=$(head -1 <<<"$lines")
	extra=$(tail -n +2 <<<"$lines" | wc -l | tr -d ' ')
	if [[ $extra -gt 0 ]]; then
		bookmark="${bookmark}(+${extra}b)"
	fi
	echo "$bookmark"
}

# Count revisions matching a revset.
# Outputs: revision count as integer, "0" for empty results.
count_changes_in_revset() {
	local revset="$1"
	local template='commit_id ++ "\n"'
	local out
	out=$(jj log --no-graph --ignore-working-copy -r "$revset" -T "$template")
	if [[ -z $out ]]; then
		echo 0
		return
	fi
	local count=0
	while IFS= read -r _; do
		((count++))
	done <<<"$out"
	echo "$count"
}

# Resolve the nearest bookmark, its distance count, and direction.
# Checks behind first (preferred), falls back to ahead.
# Outputs: "bookmark distance_count direction" (space-delimited) or nothing.
resolve_branch_distance() {
	local lines bookmark count
	lines=$(jj-bookmark-nearest 'roots(@:: & bookmarks())')
	if [[ -n $lines ]]; then
		bookmark=$(format_bookmark "$lines")
		revset="roots(@:: & bookmarks()) & ~roots(@:: & bookmarks())"
		count=$(count_changes_in_revset "$revset")
		echo "$bookmark $count ↓"
		return
	fi
	lines=$(jj-bookmark-nearest 'heads(::@ & bookmarks())')
	if [[ -n $lines ]]; then
		bookmark=$(format_bookmark "$lines")
		revset="heads(::@ & bookmarks())::@ & ~heads(::@ & bookmarks())"
		count=$(count_changes_in_revset "$revset")
		echo "$bookmark $count ↑"
		return
	fi
}

# Query the current change's status.
# Outputs: "change_id conflict_flag empty_flag" (space-separated).
query_status() {
	local template='change_id.shortest(8)'
	template+=' ++ " " ++ if(conflict, "1", "0")'
	template+=' ++ " " ++ if(empty, "1", "0")'
	template+=' ++ "\n"'
	jj log -r @ --no-graph --ignore-working-copy --color=always -T "$template"
}

# Assemble and print the ANSI-colored prompt string.
# Outputs: space-joined segments with no trailing newline.
build_prompt() {
	segments=()
	read -r bookmark distance_count direction < <(resolve_branch_distance)
	if [[ -n $bookmark ]]; then
		segments+=("${COLOR_BOLD_PURPLE}on ${bookmark}${COLOR_RESET}")
		if [[ $distance_count -gt 0 ]]; then
			segments+=("${COLOR_CYAN}${direction}${distance_count}${COLOR_RESET}")
		fi
	fi
	read -r change_id has_conflict is_empty < <(query_status)
	segments+=("$change_id")
	if [[ $has_conflict == "1" ]]; then
		segments+=("${COLOR_BOLD_RED}⚠️${COLOR_RESET}")
	fi
	if [[ $is_empty == "0" ]]; then
		segments+=("${COLOR_BOLD_YELLOW}●${COLOR_RESET}")
	fi
	printf '%s' "${segments[*]}"
}

build_prompt
