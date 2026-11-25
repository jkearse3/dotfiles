#!/usr/bin/env bash
# Fixtures for `child-watch.sh`, run as a build gate by the derivation in
# `child-watch.nix`. Takes the script under test and the real `jq`. Each
# fixture runs the script against a fake `rex` that serves blocks from files
# in a scratch directory, so no Rex server is involved:
#   rex block inspect B --json         blocks/B/inspect, or not found
#   rex window ls -s S --json          windows
#   rex block call -b B process        blocks/B/process, or not found
#   rex block call -b B program_status blocks/B/status, or no records
# Any call fails with the text of `error` when it exists, and the Nth call
# first runs on-call-N. A fake `sleep` runs on-sleep-N for the Nth sleep and
# stops the run after 40 sleeps.
set -euo pipefail
export LC_ALL=C

usage='usage: child-watch-test.sh <child-watch.sh> <jq>'
script=${1:?$usage}
jq=${2:?$usage}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
	echo "FAIL: $1" >&2
	exit 1
}

fake=$work/fake
bin=$work/bin
state=$work/state
mkdir -p "$fake/blocks" "$bin"
ln -s "$jq" "$bin/jq"
echo '{"windows":[]}' >"$fake/windows"

{
	printf '#!%s\n' "$BASH"
	printf 'fake=%q\n' "$fake"
	# shellcheck disable=SC2016 # Expanded by the fake, not here.
	printf '%s\n' \
		'[[ $1 == --autostart=false ]] || { echo "fake rex: missing --autostart=false: $*" >&2; exit 64; }' \
		'shift' \
		'count=$(( $(cat "$fake/call-count" 2>/dev/null || echo 0) + 1 )); echo "$count" >"$fake/call-count"' \
		'if [[ -e $fake/on-call-$count ]]; then bash "$fake/on-call-$count"; fi' \
		'if [[ -e $fake/error ]]; then echo "Error: $(<"$fake/error")" >&2; exit 1; fi' \
		'not_found() { echo "Error: block target \"$1\" not found" >&2; exit 3; }' \
		'case "$1 $2" in' \
		'"block inspect") [[ -e $fake/blocks/$3/inspect ]] || not_found "$3"; cat "$fake/blocks/$3/inspect" ;;' \
		'"window ls") cat "$fake/windows" ;;' \
		'"block call")' \
		'  [[ -e $fake/blocks/$4/process ]] || not_found "$4"' \
		'  case $5 in' \
		'  process) cat "$fake/blocks/$4/process" ;;' \
		'  program_status) cat "$fake/blocks/$4/status" 2>/dev/null || echo "{\"records\":[]}" ;;' \
		'  *) echo "fake rex: unexpected method $5" >&2; exit 64 ;;' \
		'  esac ;;' \
		'*) echo "fake rex: unexpected: $*" >&2; exit 64 ;;' \
		'esac'
} >"$bin/rex"
{
	printf '#!%s\n' "$BASH"
	printf 'fake=%q\n' "$fake"
	# shellcheck disable=SC2016 # Expanded by the fake, not here.
	printf '%s\n' \
		'count=$(( $(cat "$fake/sleep-count" 2>/dev/null || echo 0) + 1 )); echo "$count" >"$fake/sleep-count"' \
		'if ((count > 40)); then echo "fake sleep: too many sleeps" >&2; kill "$PPID"; exit 1; fi' \
		'if [[ -e $fake/on-sleep-$count ]]; then bash "$fake/on-sleep-$count"; fi'
} >"$bin/sleep"
chmod +x "$bin/rex" "$bin/sleep"

parent=block:00000000-0000-0000-0000-0000000000ff

# Writes block ID (block:<suffix>) in a tab labelled LABEL (empty for none),
# with a live program and no status records.
block() {
	local block=block:$1 label=$2 window=window:$1

	mkdir -p "$fake/blocks/$block"
	# shellcheck disable=SC2016 # jq variables, not shell ones.
	"$jq" -n --arg block "$block" --arg window "$window" \
		'{session_id: "session:1", block: {block_id: $block, window_id: $window, label: "shell"}}' \
		>"$fake/blocks/$block/inspect"
	# shellcheck disable=SC2016 # jq variables, not shell ones.
	"$jq" --arg window "$window" --arg label "$label" \
		'.windows += [{window_id: $window, label: (if $label == "" then null else $label end)}]' \
		"$fake/windows" >"$fake/windows.next"
	mv "$fake/windows.next" "$fake/windows"
	echo '{"child":{"pid":1},"last_exit":null}' >"$fake/blocks/$block/process"
	rm -f "$fake/blocks/$block/status"
}

# Sets block SUFFIX's status records to RECORDS, a jq array of
# [state, updated_at, id-or-null] triples.
status() {
	"$jq" -n "{records: [$2 | {state: .[0], updated_at: .[1], id: .[2]}]}" \
		>"$fake/blocks/block:$1/status"
}

# Ends block SUFFIX's program with LAST_EXIT, a JSON object.
exited() {
	echo "{\"child\":null,\"last_exit\":$2}" >"$fake/blocks/block:$1/process"
}

# Removes block SUFFIX, as closing its tab does.
closed() {
	rm -f "$fake/blocks/block:$1/process"
}

# Writes the hook run before the Nth KIND (sleep or call): shell lines run
# with the fixture's functions.
hook() {
	local kind=$1 count=$2 body=$3

	{
		declare -f block status exited closed run_second
		printf 'fake=%q jq=%q script=%q bin=%q state=%q parent=%q\n' \
			"$fake" "$jq" "$script" "$bin" "$state" "$parent"
		printf '%s\n' "$body"
	} >"$fake/on-$kind-$count"
}

# Runs a second instance with ARGS, appending its stdout to the first's.
run_second() {
	env PATH="$bin:$PATH" XDG_STATE_HOME="$state" REX_BLOCK="$parent" bash "$script" "$@"
}

# Runs the script with ARGS, leaving its stdout in $work/out and status in
# $status. Extra environment comes from WATCH_ENV.
run_watch() {
	rm -f "$fake"/on-* "$fake/sleep-count" "$fake/call-count"
	status=0
	# shellcheck disable=SC2086 # WATCH_ENV holds whole NAME=VALUE words.
	env PATH="$bin:$PATH" XDG_STATE_HOME="$state" REX_BLOCK="$parent" ${WATCH_ENV:-} \
		bash "$script" "$@" >"$work/out" 2>"$work/err" || status=$?
}

# Like run_watch, keeping the hooks already written.
run_watch_with_hooks() {
	rm -f "$fake/sleep-count" "$fake/call-count"
	status=0
	env PATH="$bin:$PATH" XDG_STATE_HOME="$state" REX_BLOCK="$parent" \
		bash "$script" "$@" >"$work/out" 2>"$work/err" || status=$?
}

expect_output() {
	local label=$1 expected=$2 expected_status=$3

	[[ $status == "$expected_status" ]] ||
		fail "$label: expected exit $expected_status, got $status; stderr: $(<"$work/err")"
	[[ $(<"$work/out") == "$expected" ]] ||
		fail "$label: expected output:"$'\n'"$expected"$'\n'"got:"$'\n'"$(<"$work/out")"
}

reset_state() {
	rm -rf "$state" "$fake/blocks" "$fake/error"
	mkdir -p "$fake/blocks"
	echo '{"windows":[]}' >"$fake/windows"
}

# Usage errors.
status=0
env -u REX_BLOCK PATH="$bin:$PATH" XDG_STATE_HOME="$state" bash "$script" >"$work/out" 2>"$work/err" || status=$?
expect_output 'no REX_BLOCK' '' 2
run_watch --bogus
expect_output 'unknown option' '' 2
run_watch --timeout soon
expect_output 'bad timeout' '' 2
run_watch 01a2
expect_output 'short block ID' '' 2

# Nothing registered.
run_watch
expect_output 'nothing registered' '' 0

# One run over a Claude child, a child whose subagent is blocked, a pi child,
# a job, and a tab closed before the first check.
block 0001 claude
status 0001 '["done", "t1", null]'
block 0002 ''
status 0002 '["working", "t1", null], ["blocked", "t1", "sub"]'
block 0003 pi
block 0004 job
exited 0004 '{"exit_code":3,"error":"exit status 3"}'
block 0005 gone
run_watch --timeout 0 block:0001 block:0002 block:0003 block:0004 block:0005
expect_output 'first check' "block:0001 claude done
block:0002 - blocked
block:0004 job exited 3" 0

closed 0005
hook sleep 1 '
status 0003 "[\"idle\", \"t1\", null]"
status 0001 "[\"done\", \"t2\", null]"
status 0002 "[\"done\", \"t2\", null], [\"working\", \"t2\", \"sub\"]"'
hook sleep 2 'status 0003 "[\"working\", \"t2\", null]"'
hook sleep 3 'status 0003 "[\"done\", \"t3\", null]"'
hook sleep 4 '
exited 0001 "{\"exit_code\":-1,\"error\":\"signal: killed\"}"
closed 0002
exited 0003 "{\"exit_code\":0}"'
run_watch_with_hooks
expect_output 'later run' "block:0005 gone exited closed
block:0002 - done
block:0003 pi done
block:0001 claude exited signal killed
block:0002 - exited closed
block:0003 pi exited 0" 0
[[ ! -e $state/rex-child-watch/$parent.lock ]] || fail 'later run: left its lock behind'

run_watch
expect_output 'repeat run' '' 0

# opencode: `idle` at startup and at a turn's end.
reset_state
block 0006 oc
status 0006 '["idle", "t1", null]'
run_watch --timeout 0 block:0006
expect_output 'startup idle' '' 0
status 0006 '["idle", "t2", null]'
run_watch --timeout 0
expect_output 'turn between runs' 'block:0006 oc done' 0
status 0006 '["idle", "t3", null]'
run_watch --timeout 0
expect_output 'idle after done' '' 0
status 0006 '["idle", "t4", null]'
run_watch --timeout 0
expect_output 'idle re-sent after done' '' 0

block 0007 oc2
status 0007 '["idle", "t1", null]'
hook sleep 1 'status 0007 "[\"idle\", \"t1\", null]"'
hook sleep 2 'status 0007 "[\"idle\", \"t2\", null]"'
run_watch_with_hooks --until-news block:0007
expect_output 'turn between two checks of one run' 'block:0007 oc2 done' 0
[[ $(<"$fake/sleep-count") == 2 ]] || fail 'until-news: did not stop at the first news'
status 0007 '["working", "t3", null]'
run_watch --timeout 0
expect_output 'working' '' 0
status 0007 '["idle", "t4", null]'
run_watch --timeout 0
expect_output 'idle after working' 'block:0007 oc2 done' 0

# An error, then the `idle` that follows it across runs: the error stays the
# last status, so a later `idle` with a newer report time is not a turn.
reset_state
block 0012 failing
status 0012 '["error", "t1", null]'
run_watch --timeout 0 block:0012
expect_output 'error' 'block:0012 failing error' 0
status 0012 '["error", "t2", null]'
run_watch --timeout 0
expect_output 'error re-sent' '' 0
status 0012 '["idle", "t3", null]'
run_watch --timeout 0
expect_output 'idle after error' '' 0
status 0012 '["idle", "t4", null]'
run_watch --timeout 0
expect_output 'idle re-sent after error' '' 0

# A second instance hands its block to the running one.
reset_state
block 0008 first
status 0008 '["working", "t1", null]'
block 0009 second
status 0009 '["blocked", "t1", null]'
hook sleep 1 'run_second block:0009'
hook sleep 2 '
exited 0008 "{\"exit_code\":0}"
exited 0009 "{\"exit_code\":0}"'
run_watch_with_hooks block:0008
expect_output 'second instance' "$parent watch-already-running
block:0009 second blocked
block:0008 first exited 0
block:0009 second exited 0" 0

# A registration that lands while the running instance is about to exit.
reset_state
block 000a done-already
exited 000a '{"exit_code":0}'
block 000b late
status 000b '["done", "t1", null]'
hook call 3 "printf 'block:000b\tlate\n' >>\"\$state/rex-child-watch/\$parent.children\""
hook sleep 1 'exited 000b "{\"exit_code\":0}"'
run_watch_with_hooks block:000a
expect_output 'registration while exiting' "block:000a done-already exited 0
block:000b late done
block:000b late exited 0" 0

# Concurrent registrations behind a live lock both land.
reset_state
block 000c one
block 000d two
mkdir -p "$state/rex-child-watch/$parent.lock"
sleep 60 &
holder=$!
echo "$holder" >"$state/rex-child-watch/$parent.lock/pid"
run_second block:000c >"$work/out-c" &
second_c=$!
run_second block:000d >"$work/out-d" &
second_d=$!
wait "$second_c" "$second_d"
[[ $(<"$work/out-c") == "$parent watch-already-running" ]] || fail "live lock: $(<"$work/out-c")"
[[ $(cut -f1 "$state/rex-child-watch/$parent.children" | sort | tr '\n' ' ') == 'block:000c block:000d ' ]] ||
	fail "concurrent registrations: $(<"$state/rex-child-watch/$parent.children")"
kill "$holder"
wait "$holder" 2>/dev/null || true

# A lock whose owner died does not block the next run.
exited 000c '{"exit_code":1,"error":"exit status 1"}'
exited 000d '{"exit_code":0}'
run_watch
sort -o "$work/out" "$work/out"
expect_output 'stale lock' "block:000c one exited 1
block:000d two exited 0" 0

# An unknown block registers nothing.
reset_state
block 000e known
run_watch block:000e block:0bad
expect_output 'unknown block' "$parent watch-failed cannot find block block:0bad" 1
[[ ! -s $state/rex-child-watch/$parent.children ]] || fail 'unknown block: registered something'

# The time limit, and a failing rex call.
status 000e '["working", "t1", null]'
WATCH_ENV=SECONDS=1500 run_watch block:000e
expect_output 'run limit' "$parent watch-ended" 0

# A failing rex call prints the lines that check already found.
reset_state
block 0010 finished
status 0010 '["done", "t1", null]'
block 0011 next
mkdir -p "$state/rex-child-watch"
printf 'block:0010\tfinished\nblock:0011\tnext\n' >"$state/rex-child-watch/$parent.children"
hook call 3 "echo 'server unreachable' >\"\$fake/error\""
run_watch_with_hooks
expect_output 'rex failure' "block:0010 finished done
$parent watch-failed server unreachable" 1

echo 'rex-child-watch fixtures passed'
