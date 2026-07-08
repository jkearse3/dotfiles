#!/usr/bin/env bash

# Interactive port listener killer with fzf multi-select.
# Lists TCP listeners via port-listeners-list, presents them in fzf,
# and sends SIGTERM to each selected process.

input=$(port-listeners-list)

if [[ $(echo "$input" | wc -l) -le 1 ]]; then
	echo "No listeners found." >&2
	exit 0
fi

selection=$(echo "$input" | fzf --multi --header-lines=1) || exit 0

if [[ -z $selection ]]; then
	exit 0
fi

while IFS= read -r line; do
	pid=$(echo "$line" | awk '{print $1}')

	if [[ -z $pid ]]; then
		continue
	fi

	if ! kill "$pid" 2>/dev/null; then
		echo "error: failed to kill PID $pid" >&2
	fi
done <<<"$selection"
