#!/usr/bin/env bash
# Fixtures for `child-watch.sh`, run as a build gate by the derivation in
# `child-watch.nix`. Takes the script under test and the real `jq`. Each
# fixture runs the script against a fake `hc` that serves terminals from JSON
# files in a scratch directory, so no hc core is involved:
#   hc get X                  get/X.json, or a not_found error
#   hc ls --all --label ...   every get/t*.json labelled role=agent, plus the
#                             addresses in ls-extra
#   hc wait ...               runs on-wait-N for the Nth wait, if present, then
#                             times out; fails with wait-error's text if present
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
mkdir -p "$fake/get" "$bin" "$work/tmp"
ln -s "$jq" "$bin/jq"
{
	printf '#!%s\n' "$BASH"
	printf 'fake=%q\n' "$fake"
	# shellcheck disable=SC2016 # Expanded by the fake, not here.
	printf '%s\n' \
		'case $1 in' \
		'get)' \
		'  if [[ -e $fake/get/$2.json ]]; then cat "$fake/get/$2.json"; exit 0; fi' \
		'  jq -nc --arg m "no terminal \"$2\"" "{error: {kind: \"not_found\", message: \$m}}"; exit 1 ;;' \
		'ls)' \
		'  { cat "$fake"/get/t*.json; touch "$fake/ls-extra"; jq -R "{address: ., labels: {role: \"agent\"}}" "$fake/ls-extra"; } |' \
		'    jq -s "{terminals: map(select(.labels.role? == \"agent\"))}" ;;' \
		'wait)' \
		'  count=$(( $(cat "$fake/wait-count" 2>/dev/null || echo 0) + 1 )); echo "$count" >"$fake/wait-count"' \
		'  if [[ -e $fake/wait-error ]]; then jq -nc --rawfile m "$fake/wait-error" "{error: {kind: \"io\", message: \$m}}"; exit 1; fi' \
		'  if [[ -e $fake/on-wait-$count ]]; then bash "$fake/on-wait-$count"; fi' \
		'  echo "{\"reason\":\"timeout\",\"children\":[]}" ;;' \
		'*) echo "fake hc: unexpected: $*" >&2; exit 64 ;;' \
		'esac'
} >"$bin/hc"
chmod +x "$bin/hc"

# Writes terminal ADDRESS as `hc get` shows it. FIELDS is a jq object merged
# over a live, unnamed terminal with no parent, labels, or status.
terminal() {
	local address=$1 fields=$2

	"$jq" -n --arg address "$address" "{address: \$address, name: null, parent: null, labels: {}, state: \"live\", status: null, turn: 0, exit_code: null, signal: null} + $fields" \
		>"$fake/get/$address.json"
}

# Writes an agent child of t1 with NAME (null for none), STATE, STATUS (null
# for none), TURN, and extra FIELDS.
agent() {
	local address=$1 name=$2 state=$3 status=$4 turn=$5 fields=${6:-}

	[[ -n $fields ]] || fields='{}'
	terminal "$address" "{name: $name, parent: \"t1\", labels: {role: \"agent\"}, state: \"$state\", status: (if \"$status\" == \"null\" then null else {app: \"claude-code\", state: \"$status\"} end), turn: $turn} + $fields"
}

# Writes the Nth wait's hook: shell lines run with the fixture's functions.
on_wait() {
	local count=$1 body=$2

	{
		declare -f terminal agent
		printf 'fake=%q jq=%q\n' "$fake" "$jq"
		printf '%s\n' "$body"
	} >"$fake/on-wait-$count"
}

# Runs the script with ARGS, leaving its stdout in $work/out and status in
# $status. Extra environment comes from WATCH_ENV.
run_watch() {
	rm -f "$fake/wait-count"
	status=0
	# shellcheck disable=SC2086 # WATCH_ENV holds whole NAME=VALUE words.
	env -u HC_TERMINAL_ID PATH="$bin:$PATH" TMPDIR="$work/tmp/" ${WATCH_ENV:-} \
		bash "$script" "$@" >"$work/out" 2>"$work/err" || status=$?
}

expect_output() {
	local label=$1 expected=$2 expected_status=$3

	[[ $status == "$expected_status" ]] ||
		fail "$label: expected exit $expected_status, got $status; stderr: $(<"$work/err")"
	[[ $(<"$work/out") == "$expected" ]] ||
		fail "$label: expected output:"$'\n'"$expected"$'\n'"got:"$'\n'"$(<"$work/out")"
}

run_watch
expect_output usage '' 2

terminal t1 '{name: "lead"}'
cp "$fake/get/t1.json" "$fake/get/lead.json"

agent t2 '"rev"' live 'done' 1
agent t3 null live blocked 1
terminal t4 '{parent: "t1", state: "finished", exit_code: 1}'
agent t5 '"other"' live 'done' 1 '{parent: "t9"}'
agent t6 '"boot"' live idle 0
agent t7 '"crash"' finished null 1 '{exit_code: 3}'
echo t8 >"$fake/ls-extra"
on_wait 1 '
agent t3 null live done 1
agent t6 "\"boot\"" live idle 1'
on_wait 2 '
agent t2 "\"rev\"" finished null 1 "{signal: 9}"
agent t3 null finished null 1
agent t6 "\"boot\"" finished null 1 "{exit_code: 0}"'

run_watch lead
expect_output 'parent by name' "t2 rev done
t3 - blocked
t7 crash exited 3
t3 - done
t6 boot done
t2 rev exited signal 9
t3 - exited killed
t6 boot exited 0" 0
[[ ! -e $work/tmp/hc-child-watch/t1.lock ]] || fail 'parent by name: left its lock behind'

agent t10 null finished null 2 '{exit_code: 5}'
run_watch t1
expect_output 'parent by address, change between runs' 't10 - exited 5' 0

run_watch t1
expect_output 'repeat run' '' 0

sleep 60 &
holder=$!
mkdir "$work/tmp/hc-child-watch/t1.lock"
echo "$holder" >"$work/tmp/hc-child-watch/t1.lock/pid"
run_watch t1
expect_output 'live lock' 't1 watch-already-running' 0
kill "$holder"
wait "$holder" 2>/dev/null || true
run_watch t1
expect_output 'stale lock' '' 0

agent t11 '"slow"' live working 0
WATCH_ENV=SECONDS=1500 run_watch t1
expect_output 'run limit' 't1 watch-ended' 0

agent t12 '"late"' live 'done' 1
echo 'core down' >"$fake/wait-error"
run_watch t1
expect_output 'wait failure' 't12 late done
t1 watch-failed core down' 1
rm "$fake/wait-error"

run_watch ghost
expect_output 'unknown parent' 'ghost watch-failed cannot resolve parent ghost: no terminal "ghost"' 1

status=0
PATH="$bin:$PATH" TMPDIR="$work/tmp/" HC_TERMINAL_ID=lead SECONDS=1500 bash "$script" >"$work/out" 2>"$work/err" || status=$?
expect_output 'parent from HC_TERMINAL_ID' 't1 watch-ended' 0

echo 'child-watch fixtures passed'
