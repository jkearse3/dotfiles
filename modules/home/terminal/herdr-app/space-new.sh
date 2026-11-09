#!/usr/bin/env bash
# Picks a folder under the home directory with fzf and makes a Herdr app
# space there. The `space-new` mod runs it in a popup terminal, which closes
# when it exits.
#
# Usage: space-new.sh FD FZF HERDR_APP
#   FD, FZF, HERDR_APP  absolute paths of the tools, so the result does not
#                       depend on the PATH of whoever started the core.
#
# The candidates are every directory `fd` lists under $HOME with its default
# filtering (no hidden or gitignored folders), except `~/go` and
# `~/Library`; a `go` or `Library` folder deeper down is still listed. The
# space gets no name, so the app names it after where its first terminal is.
# Esc, or Enter with no match, makes nothing and exits 0. When fzf fails or
# the app rejects the space, the error stays on screen until Enter, then the
# script exits nonzero.
set -euo pipefail

usage='usage: space-new.sh FD FZF HERDR_APP'
fd=${1:?$usage}
fzf=${2:?$usage}
herdr_app=${3:?$usage}

# Prints MESSAGE and waits for Enter, because the popup would otherwise
# close before it could be read, then exits 1.
fail_and_hold() {
	local message=$1

	printf 'error: %s\n\nPress enter to close.' "$message" >&2
	read -r || true
	exit 1
}

# Process substitution rather than a pipe: fzf exits on a pick while fd may
# still be listing, and fd then exits 1, which under pipefail reads as fzf's
# "no match", so the pick would make nothing.
status=0
pick=$("$fzf" --scheme=path --read0 --prompt 'New space> ' < <(
	"$fd" --type d --exclude /go --exclude /Library --strip-cwd-prefix --print0 --base-directory "$HOME"
)) || status=$?
case $status in
0) ;;
# 1: Enter with no match; 130: Esc or ctrl-c.
1 | 130) exit 0 ;;
*) fail_and_hold "fzf exited with $status" ;;
esac

# fzf ends the pick with a newline, which command substitution drops; fd
# ends each directory with a slash, which keeps a name ending in a newline
# whole.
pick=${pick%/}

output=$("$herdr_app" "do" space.new --folder "$HOME/$pick" 2>&1) || fail_and_hold "$output"
