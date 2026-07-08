#!/usr/bin/env bash

# List TCP listeners as a PID / COMMAND / ADDRESS table.
# Parses lsof -F field-per-line output where each record is a sequence of
# p<PID>, c<command>, and n<address> lines.

printf "%-8s  %-20s  %s\n" "PID" "COMMAND" "ADDRESS"

lsof -nP -iTCP -sTCP:LISTEN -Fpcn 2>/dev/null |
	awk '
		/^p/ { pid = substr($0, 2); cmd = "" }
		/^c/ { cmd = substr($0, 2) }
		/^n/ && pid && cmd {
			addr = substr($0, 2)
			if (!seen[pid, addr]++) printf "%-8s  %-20s  %s\n", pid, cmd, addr
		}
	' || exit 0
