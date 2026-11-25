#!/usr/bin/env bash
# Prints one line per change in the agent children a parent Rex pane
# registers, so an agent can learn of them without anything typed into its
# input box. Claude Code runs it under its Monitor tool, which turns each
# stdout line into a notification; other agents run it with --until-news.
#
# Usage: rex-child-watch [--until-news] [--timeout SECONDS] [BLOCK...]
#   BLOCK         full block ID (block:<uuid>) of an agent child to register
#                 before watching; registered children stay registered
#   --until-news  also exit after a check that printed a line
#   --timeout     stop after SECONDS (default 1440); 0 makes one check
#
# The parent is the pane named by $REX_BLOCK. Rex has no parent/child link,
# so the parent registers each child it starts, and each child is named by
# its tab's label (`-` when there is none). Lines, flushed as printed:
#   <block> <name> done             a turn ended: `done`, or `idle` as below
#   <block> <name> blocked          it is waiting on a prompt
#   <block> <name> error            it reported an error
#   <block> <name> exited <code>    `exited 3`, `exited signal killed`, or `exited closed`
#   <parent> watch-already-running  another instance watches this parent; it
#                                   takes over this run's registrations
#   <parent> watch-ended            --timeout passed
#   <parent> watch-failed <message> a rex call failed; exit status 1
#
# A child's status is `blocked` when any of its OSC 7501 status records is,
# else its root record's state. `done`, `blocked`, and `error` print when they
# differ from the child's last recorded status. `idle` prints `done` after
# `working` or `blocked`, or after an `idle` with an older report time (a turn
# whose `working` fell between two checks or ran while no watcher did). The
# first `idle` recorded for a child prints nothing, because pi and opencode
# report `idle` at startup too. See rex-behavior.md.
#
# State lives under $XDG_STATE_HOME/rex-child-watch, keyed by the parent's
# block ID, so a parent resumed in the same pane finds its children. Each line
# is printed before it is recorded, so a line that fails to print is printed
# by the next run. It exits 0 once no registered child is live (not yet
# reported exited), or with nothing registered. A usage error exits 2.
set -euo pipefail

# shellcheck disable=SC2016 # Names the variable, not its value.
usage='usage: rex-child-watch [--until-news] [--timeout SECONDS] [BLOCK...]  (parent: $REX_BLOCK)'
block_pattern='^block:[0-9a-f-]+$'
poll_seconds=2

usage_error() {
	echo "rex-child-watch: $1" >&2
	echo "$usage" >&2
	exit 2
}

until_news=false
timeout_seconds=1440
new_blocks=()
while (($# > 0)); do
	case $1 in
	--until-news) until_news=true ;;
	--timeout)
		[[ ${2:-} =~ ^[0-9]+$ ]] || usage_error "--timeout needs a whole number of seconds"
		timeout_seconds=$2
		shift
		;;
	-*) usage_error "unknown option $1" ;;
	*)
		[[ $1 =~ $block_pattern ]] || usage_error "not a full block ID: '$1'"
		new_blocks+=("$1")
		;;
	esac
	shift
done

parent=${REX_BLOCK:-}
[[ $parent =~ $block_pattern ]] || usage_error 'REX_BLOCK does not hold a full block ID'

# Prints `watch-failed` with MESSAGE flattened to one line and exits 1.
fail_watch() {
	local message=$1

	printf '%s watch-failed %s\n' "$parent" "$(tr '\n' ' ' <<<"$message" | sed 's/ *$//')"
	exit 1
}

# Runs `rex ARGS...` without starting a server and prints its stdout. A
# failure prints Rex's error message instead and returns 3 when Rex reports
# the target not found, else 1.
rex_call() {
	local output status=0 errors

	errors=$(mktemp)
	output=$(rex --autostart=false "$@" </dev/null 2>"$errors") || status=$?
	if ((status == 0)); then
		rm -f "$errors"
		printf '%s\n' "$output"
		return 0
	fi

	output=$(sed 's/^Error: //' "$errors" | grep -v '^$' | head -n 1)
	rm -f "$errors"
	printf '%s\n' "${output:-rex exited with status $status}"
	if [[ $output == *"not found"* ]]; then
		return 3
	fi
	return 1
}

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/rex-child-watch
mkdir -p "$state_dir"
# Tab-separated `<block> <name>`, appended by every instance.
registry=$state_dir/$parent.children
# Tab-separated `<block> <status> <updated_at>`, written by the lock
# holder only. `exited` is a status too.
memory=$state_dir/$parent.status
touch "$registry" "$memory"

# Sets tab_label to the label of BLOCK's tab, or `-` when the tab has none
# or cannot be listed. Fails the watch when BLOCK is unknown.
look_up_tab_label() {
	local block=$1 inspect windows

	inspect=$(rex_call block inspect "$block" --json) || {
		(($? == 3)) && fail_watch "cannot find block $block"
		fail_watch "$inspect"
	}
	tab_label=
	if windows=$(rex_call window ls -s "$(jq -r '.session_id' <<<"$inspect")" --json); then
		tab_label=$(jq -r --arg window "$(jq -r '.block.window_id' <<<"$inspect")" \
			'first(.windows[] | select(.window_id == $window) | .label) // empty' <<<"$windows")
	fi
	tab_label=${tab_label:--}
}

# Whether BLOCK is in the registry.
is_registered() {
	awk -F '\t' -v block="$1" '$1 == block { found = 1 } END { exit !found }' "$registry"
}

# Registers every BLOCK argument, or none when one is unknown. Appends one
# line per block so concurrent registrations cannot overwrite each other;
# readers keep each block's first line.
if ((${#new_blocks[@]} > 0)); then
	lines=
	for block in "${new_blocks[@]}"; do
		if ! is_registered "$block"; then
			look_up_tab_label "$block"
			lines+="$block"$'\t'"$tab_label"$'\n'
		fi
	done
	printf '%s' "$lines" >>"$registry"
fi

# One instance per parent: a directory lock holding the owner's PID, so a
# lock whose owner died is taken over instead of blocking.
lock=$state_dir/$parent.lock
take_lock() {
	local owner

	if mkdir "$lock" 2>/dev/null; then
		echo $$ >"$lock/pid"
		return 0
	fi
	owner=$(cat "$lock/pid" 2>/dev/null || true)
	if [[ -n $owner ]] && kill -0 "$owner" 2>/dev/null; then
		return 1
	fi
	rm -rf "$lock"
	mkdir "$lock" 2>/dev/null || return 1
	echo $$ >"$lock/pid"
}
release_lock() {
	if [[ $(cat "$lock/pid" 2>/dev/null) == "$$" ]]; then
		rm -rf "$lock"
	fi
}

if ! take_lock; then
	printf '%s watch-already-running\n' "$parent"
	exit 0
fi
trap release_lock EXIT
trap 'exit 143' TERM HUP INT
# A closed stdout makes printf fail, so the run exits, instead of a SIGPIPE
# killing it before the EXIT trap releases the lock.
trap '' PIPE

# Prints the registered blocks with their names, first registration wins.
registered_children() {
	awk -F '\t' '!seen[$1]++' "$registry"
}

# Prints BLOCK's recorded `<status> <updated_at>`, if any.
recorded_status() {
	awk -F '\t' -v block="$1" '$1 == block { print $2 "\t" $3 }' "$memory"
}

# Records STATUS with UPDATED_AT for BLOCK, replacing its earlier record.
record_status() {
	local block=$1 status=$2 updated_at=$3 next

	next=$(mktemp "$state_dir/.status.XXXXXX")
	awk -F '\t' -v block="$block" '$1 != block' "$memory" >"$next"
	printf '%s\t%s\t%s\n' "$block" "$status" "$updated_at" >>"$next"
	mv "$next" "$memory"
}

# Prints the line for one child, records what it saw, and adds to
# live_child_count and printed_count.
check_child() {
	local block=$1 name=$2 process status_json derived status updated_at
	local last last_status last_updated line=

	last=$(recorded_status "$block")
	IFS=$'\t' read -r last_status last_updated <<<"$last" || true
	[[ $last_status == exited ]] && return 0

	process=$(rex_call block call -b "$block" process) || {
		(($? == 3)) || fail_watch "$process"
		line="$block $name exited closed"
	}
	if [[ -z $line ]]; then
		line=$(jq -r --arg prefix "$block $name" '
			.last_exit // empty
			| if .exit_code >= 0 then "\($prefix) exited \(.exit_code)"
			else "\($prefix) exited signal \(.error // "unknown" | sub("^signal: "; ""))" end
		' <<<"$process")
	fi
	if [[ -n $line ]]; then
		printf '%s\n' "$line"
		record_status "$block" exited -
		printed_count=$((printed_count + 1))
		return 0
	fi
	live_child_count=$((live_child_count + 1))

	status_json=$(rex_call block call -b "$block" program_status) || fail_watch "$status_json"
	derived=$(jq -r '
		.records as $records
		| (first($records[] | select(.state == "blocked"))
			// first($records[] | select(.id == null))
			// $records[0]
			// empty)
		| "\(.state)\t\(.updated_at)"
	' <<<"$status_json")
	[[ -n $derived ]] || return 0
	IFS=$'\t' read -r status updated_at <<<"$derived"

	case $status in
	working) ;;
	"done" | blocked | error)
		[[ $last_status != "$status" ]] && line="$block $name $status"
		;;
	idle)
		if [[ $last_status == working || $last_status == blocked ]] ||
			[[ $last_status == idle && $last_updated != "$updated_at" ]]; then
			line="$block $name done"
			status="done"
		elif [[ $last_status == "done" || $last_status == error ]]; then
			# The turn's end is already reported; keep it as the last status.
			return 0
		fi
		;;
	*) return 0 ;;
	esac

	if [[ -n $line ]]; then
		printf '%s\n' "$line"
		printed_count=$((printed_count + 1))
	fi
	if [[ $status != "$last_status" || $updated_at != "$last_updated" ]]; then
		record_status "$block" "$status" "$updated_at"
	fi
}

# Checks every registered child not yet reported exited.
check_children() {
	local block name

	live_child_count=0
	printed_count=0
	while IFS=$'\t' read -r block name; do
		[[ -n $block ]] || continue
		check_child "$block" "${name:--}"
	done < <(registered_children)
}

# Whether a registered child has not been reported exited.
has_unexited_child() {
	local block status

	while IFS=$'\t' read -r block _; do
		[[ -n $block ]] || continue
		IFS=$'\t' read -r status _ <<<"$(recorded_status "$block")" || true
		[[ $status == exited ]] || return 0
	done < <(registered_children)
	return 1
}

while true; do
	check_children

	if $until_news && ((printed_count > 0)); then
		exit 0
	fi

	if ((live_child_count == 0)); then
		# A child registered by an instance that saw this lock may not have
		# been checked yet; releasing first means either this run sees it
		# here or the registering run could take the lock.
		release_lock
		if has_unexited_child && take_lock; then
			continue
		fi
		exit 0
	fi

	if ((timeout_seconds == 0)); then
		exit 0
	fi
	if ((SECONDS >= timeout_seconds)); then
		printf '%s watch-ended\n' "$parent"
		exit 0
	fi

	remaining=$((timeout_seconds - SECONDS))
	sleep $((remaining < poll_seconds ? remaining : poll_seconds))
done
