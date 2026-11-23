#!/usr/bin/env bash
# Prints one line per change in a parent terminal's agent children, so an
# agent can learn of them without hc typing into its input box. Claude Code
# runs it under its Monitor tool, which turns each stdout line into a
# notification.
#
# Usage: hc-child-watch [PARENT]
#   PARENT  hc address or name of the parent terminal; defaults to
#           $HC_TERMINAL_ID.
#
# Agent children are the parent's children carrying the label `role=agent`;
# jobs, servers, and other terminals are ignored. Lines, flushed as printed:
#   <address> <name> done             it left `working` and is neither blocked nor in error
#   <address> <name> blocked          it is waiting on a prompt
#   <address> <name> error            it reported an error
#   <address> <name> exited <code>    `exited 3`, `exited signal 9`, or `exited killed`
#   <parent> watch-already-running    another instance watches this parent
#   <parent> watch-ended              it stopped itself before Monitor's 30-minute limit
#   <parent> watch-failed <message>   an hc call failed; exit status 1
# `<name>` is `-` for an unnamed child. A child prints `done`, `blocked`, or
# `error` at most once per turn and `exited` once; startup `idle` (turn 0)
# prints nothing. What it printed is remembered per parent under $TMPDIR, so
# a later run never repeats a line and reports changes made while no run was
# active.
#
# It reads each child's state from `hc get` rather than from `hc wait` news,
# which misses turns that end while no wait runs and never reports kills;
# `hc wait` serves only to wake it early. It exits 0 once the parent has no
# live agent child, or with `watch-ended` after about 24 minutes (counted by
# bash's SECONDS, which the fixtures preset). A usage error exits 2.
set -euo pipefail

parent_arg=${1:-${HC_TERMINAL_ID:-}}
if [[ -z $parent_arg || $# -gt 1 ]]; then
	# shellcheck disable=SC2016 # Names the variable, not its value.
	echo 'usage: hc-child-watch [PARENT]  (PARENT defaults to $HC_TERMINAL_ID)' >&2
	exit 2
fi

run_limit_seconds=1440
wait_timeout_seconds=30

# The parent as its own lines name it: the resolved address once known.
parent_label=$parent_arg

# Prints `watch-failed` with MESSAGE flattened to one line and exits 1.
fail_watch() {
	local message=$1

	printf '%s watch-failed %s\n' "$parent_label" "$(tr '\n' ' ' <<<"$message" | sed 's/ *$//')"
	exit 1
}

# Runs `hc ARGS... --json` and prints its JSON. A failure prints hc's error
# message instead and returns 3 when hc reports `not_found`, else 1.
hc_json() {
	local output status=0

	output=$(hc "$@" --json 2>&1) || status=$?
	if ((status == 0)); then
		printf '%s\n' "$output"
		return 0
	fi

	jq -r '.error.message? // empty' <<<"$output" 2>/dev/null | grep . || printf '%s\n' "$output"
	if [[ $(jq -r '.error.kind? // empty' <<<"$output" 2>/dev/null) == not_found ]]; then
		return 3
	fi
	return 1
}

parent_json=$(hc_json get "$parent_arg") || fail_watch "cannot resolve parent $parent_arg: $parent_json"
parent=$(jq -r '.address' <<<"$parent_json")
parent_label=$parent

state_dir=${TMPDIR:-/tmp}/hc-child-watch
mkdir -p "$state_dir"
memory=$state_dir/$parent.printed
touch "$memory"

# One instance per parent: a directory lock holding the owner's PID, so a
# lock whose owner died is taken over instead of blocking.
lock=$state_dir/$parent.lock
if ! mkdir "$lock" 2>/dev/null; then
	owner=$(cat "$lock/pid" 2>/dev/null || true)
	if [[ -n $owner ]] && kill -0 "$owner" 2>/dev/null; then
		printf '%s watch-already-running\n' "$parent"
		exit 0
	fi
	rm -rf "$lock"
	mkdir "$lock"
fi
echo $$ >"$lock/pid"

wait_pid=
release() {
	if [[ -n $wait_pid ]]; then
		kill "$wait_pid" 2>/dev/null || true
	fi
	rm -rf "$lock"
}
trap release EXIT
trap 'exit 143' TERM HUP INT

# Prints the line for each agent child's change not yet in the memory and
# sets live_agent_count to the number of agent children still live.
report_agent_children() {
	local listing address child line

	live_agent_count=0
	listing=$(hc_json ls --all --label role=agent) || fail_watch "$listing"

	while read -r address; do
		child=$(hc_json get "$address") || {
			(($? == 3)) && continue
			fail_watch "$child"
		}

		line=$(jq -r --arg parent "$parent" '
			select(.parent == $parent)
			| (.name // "-") as $name
			| if .state == "finished" then
				"\(.address) \($name) exited \(
					if .exit_code != null then .exit_code
					elif .signal != null then "signal \(.signal)"
					else "killed" end)"
			elif (.turn // 0) > 0 and .status.state? != null and .status.state != "working" then
				"\(.address) \($name) \(
					if .status.state == "blocked" or .status.state == "error" then .status.state
					else "done" end) \(.turn)"
			else empty end,
			if .state == "live" then "live" else empty end
		' <<<"$child")

		if grep -qx live <<<"$line"; then
			live_agent_count=$((live_agent_count + 1))
		fi
		line=$(grep -vx live <<<"$line" || true)
		[[ -n $line ]] || continue

		# The memory keys a turn's line by its turn, which the output omits.
		if ! grep -qxF -- "$line" "$memory"; then
			echo "$line" >>"$memory"
			case $line in
			*" exited "*) printf '%s\n' "$line" ;;
			*) printf '%s\n' "${line% *}" ;;
			esac
		fi
	done < <(jq -r '.terminals[].address' <<<"$listing")
}

while true; do
	report_agent_children
	if ((live_agent_count == 0)); then
		# A child may have started between the listing and now.
		report_agent_children
		((live_agent_count == 0)) && exit 0
	fi

	if ((SECONDS >= run_limit_seconds)); then
		printf '%s watch-ended\n' "$parent"
		exit 0
	fi

	# In the background so a signal can stop it instead of leaving an
	# orphaned wait that takes the parent's next news.
	hc wait --children any --timeout "$wait_timeout_seconds" "$parent" --json >"$state_dir/$parent.wait" 2>&1 &
	wait_pid=$!
	if ! wait "$wait_pid"; then
		wait_pid=
		fail_watch "$(jq -r '.error.message? // empty' "$state_dir/$parent.wait" 2>/dev/null | grep . || cat "$state_dir/$parent.wait")"
	fi
	wait_pid=
done
