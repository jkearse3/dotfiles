#!/usr/bin/env bash

for push_argument in "$@"; do
	case $push_argument in
	-b | -b?* | --bookmark | --bookmark=*) ;;
	-t | -t?* | --tag | --tag=*) ;;
	--all | --tracked | --deleted) ;;
	-r | -r?* | --revision | --revision=*) ;;
	-c | -c?* | --change | --change=*) ;;
	--named | --named=*) ;;
	*) continue ;;
	esac

	echo "jj-bookmark-push: push selector option is not supported: $push_argument" >&2
	exit 2
done

bookmark_template='if(!remote, name ++ "\n")'
bookmarks=$(jj bookmark list --color=never --template "$bookmark_template") || {
	echo "jj-bookmark-push: failed to list bookmarks" >&2
	exit 1
}

if [[ -z $bookmarks ]]; then
	exit 0
fi

fzf_status=0
selection=$(printf '%s\n' "$bookmarks" | fzf --multi --prompt='Bookmarks to push> ') || fzf_status=$?
case $fzf_status in
0) ;;
1 | 130) exit 0 ;;
*) exit "$fzf_status" ;;
esac

if [[ -z $selection ]]; then
	exit 0
fi

bookmark_arguments=()
while IFS= read -r bookmark; do
	if [[ -n $bookmark ]]; then
		bookmark_arguments+=(--bookmark "exact:$bookmark")
	fi
done <<<"$selection"

jj git push "$@" "${bookmark_arguments[@]}"
