#!/usr/bin/env bash

# Rebase several local bookmarks onto one destination in a single jj rebase.
#
# Usage: jj-bookmark-rebase [DESTINATION]
#
# DESTINATION is any jj revset. Without it, a first picker chooses a local
# bookmark as the destination and a second picker chooses what to rebase.

if (($# > 1)); then
	echo "usage: jj-bookmark-rebase [DESTINATION]" >&2
	exit 2
fi

# fzf exits 1 when nothing matched and 130 when cancelled; both mean no rebase.
exit_unless_picked() {
	case $1 in
	0) ;;
	1 | 130) exit 0 ;;
	*) exit "$1" ;;
	esac
}

# The name field is already quoted as a revset symbol when needed.
bookmark_template='if(!remote, name ++ "\n")'
bookmarks=$(jj bookmark list --color=never --template "$bookmark_template") || {
	echo "jj-bookmark-rebase: failed to list bookmarks" >&2
	exit 1
}

if [[ -z $bookmarks ]]; then
	exit 0
fi

if (($# == 1)); then
	destination=$1
	candidates=$bookmarks
	candidates_header='Mark the bookmarks to rebase (Tab), then Enter'
else
	picker_status=0
	destination_bookmark=$(printf '%s\n' "$bookmarks" | fzf \
		--prompt='Destination> ' \
		--header='Step 1 of 2: choose the bookmark to rebase onto') || picker_status=$?
	exit_unless_picked "$picker_status"

	IFS= read -r destination_bookmark <<<"$destination_bookmark"
	if [[ -z $destination_bookmark ]]; then
		exit 0
	fi

	destination="bookmarks(exact:$destination_bookmark)"
	candidates=$(printf '%s\n' "$bookmarks" | grep -Fxv -- "$destination_bookmark") || true
	candidates_header='Step 2 of 2: mark the bookmarks to rebase (Tab), then Enter'
fi

if [[ -z $candidates ]]; then
	exit 0
fi

picker_status=0
selection=$(printf '%s\n' "$candidates" | fzf --multi \
	--prompt="Rebase onto $destination> " \
	--header="$candidates_header") || picker_status=$?
exit_unless_picked "$picker_status"

branch_arguments=()
while IFS= read -r bookmark; do
	if [[ -n $bookmark ]]; then
		branch_arguments+=(--branch "bookmarks(exact:$bookmark)")
	fi
done <<<"$selection"

if ((${#branch_arguments[@]} == 0)); then
	exit 0
fi

jj rebase --destination "$destination" "${branch_arguments[@]}"
