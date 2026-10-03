#!/usr/bin/env bash

# List TCP listeners as a PID / COMMAND / ADDRESS table.
# With -k, pick listeners in fzf and send each one SIGTERM.
# Usage: ports [-k]

list() {
	printf "%-8s  %-20s  %s\n" "PID" "COMMAND" "ADDRESS"

	# lsof -F emits one field per line: p<PID>, c<command>, n<address>.
	# It exits non-zero when nothing is listening.
	lsof -nP -iTCP -sTCP:LISTEN -Fpcn 2>/dev/null |
		awk '
			/^p/ { pid = substr($0, 2); cmd = "" }
			/^c/ { cmd = substr($0, 2) }
			/^n/ && pid && cmd {
				addr = substr($0, 2)
				if (!seen[pid, addr]++) printf "%-8s  %-20s  %s\n", pid, cmd, addr
			}
		' || true
}

case "${1:-}" in
"")
	list
	;;
-k | --kill)
	selection=$(list | fzf --multi --header-lines=1) || exit 0
	awk '{ print $1 }' <<<"$selection" | sort -u | xargs -r kill
	;;
*)
	echo "usage: ports [-k]" >&2
	exit 2
	;;
esac
