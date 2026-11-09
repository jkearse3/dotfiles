#!/usr/bin/env bash
# Picks a folder under the home directory with fzf and makes a Herdr app
# space there. The `space-new` mod runs it in a popup terminal, which closes
# when it exits.
#
# Usage: space-new.sh FD FZF HERDR_APP CURRENT
#   FD, FZF, HERDR_APP  absolute paths of the tools, so the result does not
#                       depend on the PATH of whoever started the core.
#   CURRENT             absolute path of the folder to offer first (the
#                       focused terminal's), so Enter with an empty query
#                       makes the space there.
#
# After CURRENT come every directory `fd` lists under $HOME with its default
# filtering (no hidden or gitignored folders), except `~/go` and
# `~/Library`; a `go` or `Library` folder deeper down is still listed.
# Folders under $HOME show relative to it, as `fd` prints them (`a/b/`), so
# CURRENT is not listed twice; $HOME itself and folders outside it show as
# absolute paths. The space gets no name, so the app names it after where
# its first terminal is.
# Esc, or Enter with no match, makes nothing and exits 0. When fzf fails or
# the app rejects the space, the error stays on screen until Enter, then the
# script exits nonzero.
set -euo pipefail

usage='usage: space-new.sh FD FZF HERDR_APP CURRENT'
fd=${1:?$usage}
fzf=${2:?$usage}
herdr_app=${3:?$usage}
current=${4:?$usage}

# Prints MESSAGE and waits for Enter, because the popup would otherwise
# close before it could be read, then exits 1.
fail_and_hold() {
	local message=$1

	printf 'error: %s\n\nPress enter to close.' "$message" >&2
	read -r || true
	exit 1
}

[[ $current == /* ]] || fail_and_hold "CURRENT is not an absolute path: $current"

# CURRENT as the list shows it, ending in a slash like every `fd` entry.
# `${current%/}` is empty for the root, which then shows as `/`.
case ${current%/} in
"$HOME") current_shown=$HOME/ ;;
"$HOME"/*) current_shown=${current#"$HOME"/} current_shown=${current_shown%/}/ ;;
*) current_shown=${current%/}/ ;;
esac

# Process substitution rather than a pipe: fzf exits on a pick while fd may
# still be listing, and fd then exits 1, which under pipefail reads as fzf's
# "no match", so the pick would make nothing. The substitution's own status
# goes unchecked, so neither that nor grep's exit 1 when it passes nothing
# (CURRENT is the only folder) counts as fzf failing.
status=0
pick=$("$fzf" --scheme=path --read0 --prompt 'New space> ' < <(
	printf '%s\0' "$current_shown"
	"$fd" --type d --exclude /go --exclude /Library --strip-cwd-prefix --print0 --base-directory "$HOME" |
		grep --null-data --invert-match --line-regexp --fixed-strings --regexp "$current_shown"
)) || status=$?
case $status in
0) ;;
# 1: Enter with no match; 130: Esc or ctrl-c.
1 | 130) exit 0 ;;
*) fail_and_hold "fzf exited with $status" ;;
esac

# fzf ends the pick with a newline, which command substitution drops; every
# entry ends with a slash, which keeps a name ending in a newline whole. An
# absolute entry is the folder itself, where `/` alone stands for the root;
# any other is relative to $HOME.
case $pick in
/*)
	folder=${pick%/}
	folder=${folder:-/}
	;;
*) folder=$HOME/${pick%/} ;;
esac

output=$("$herdr_app" "do" space.new --folder "$folder" 2>&1) || fail_and_hold "$output"
