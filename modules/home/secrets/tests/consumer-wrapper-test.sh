#!/usr/bin/env bash
# Execute Pi/OpenCode's real module-generated wrappers with disposable substitutes.
set -euo pipefail
mkdir -p "$TEST_ROOT"
export HOME="$TEST_ROOT/home" XDG_CONFIG_HOME="$TEST_ROOT/config"
export XDG_DATA_HOME="$TEST_ROOT/data" XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_CACHE_HOME="$TEST_ROOT/cache" CONSUMER_TRACE="$TEST_ROOT/trace"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
export EXA_API_KEY=ambient EXCLUDED=excluded UNRELATED=preserved

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
run_status() {
	local expected=$1 actual=0
	shift
	: >"$CONSUMER_TRACE"
	"$@" >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr" || actual=$?
	[[ $actual == "$expected" ]] || fail "expected status $expected, got $actual"
}

# Store paths have no whitespace; the list comes only from the Nix fixture.
read -r -a wrappers <<<"$CONSUMER_WRAPPERS"
[[ ${#wrappers[@]} == 4 ]] || fail 'missing consumer variants'
for wrapper in "${wrappers[@]}"; do
	run_status 23 env CHILD_STATUS=23 "$wrapper" '' 'two words' '--flag'
	printf '%s\n' launcher inspect >"$TEST_ROOT/expected-trace"
	if [[ ${wrapper##*/} == nono-* ]]; then
		printf '%s\n' sandbox >>"$TEST_ROOT/expected-trace"
	fi
	printf '%s\n' child >>"$TEST_ROOT/expected-trace"
	cmp "$TEST_ROOT/expected-trace" "$CONSUMER_TRACE"
	grep -qxF EXA_API_KEY=ambient "$TEST_ROOT/environment"
	grep -qxF UNRELATED=preserved "$TEST_ROOT/environment"
	grep -qxF TEST_INTERACTIVE_POLICY=applied "$TEST_ROOT/environment"
	if grep -q '^EXCLUDED=' "$TEST_ROOT/environment"; then fail 'excluded inherited secret'; fi
	if [[ ${wrapper##*/} == *opencode ]]; then
		grep -qxF OPENCODE_ENABLE_EXA=1 "$TEST_ROOT/environment"
		grep -qxF OPENCODE_DISABLE_AUTOUPDATE=1 "$TEST_ROOT/environment"
	fi
	printf '%s\0' '' 'two words' '--flag' >"$TEST_ROOT/expected-argv"
	cmp "$TEST_ROOT/expected-argv" "$TEST_ROOT/argv"

	# Resolution errors stop before entering the sandbox or consumer.
	run_status 37 env PROVIDER_LIST='dotfiles = dotenv://fixture' "$wrapper"
	printf '%s\n' launcher inspect >"$TEST_ROOT/expected-trace"
	cmp "$TEST_ROOT/expected-trace" "$CONSUMER_TRACE"
	run_status 1 env INSPECT_STATUS=9 "$wrapper"
	cmp "$TEST_ROOT/expected-trace" "$CONSUMER_TRACE"
done
printf '%s\n' 'ok - Pi/OpenCode normal and sandbox wrappers preserve order, environment, argv and status'

read -r -a wrappers <<<"$REQUIRED_CONSUMER_WRAPPERS"
[[ ${#wrappers[@]} == 4 ]] || fail 'missing required consumer variants'
for wrapper in "${wrappers[@]}"; do
	run_status 1 "$wrapper"
	grep -qF 'not commissioned' "$TEST_ROOT/stderr"
	printf '%s\n' launcher inspect >"$TEST_ROOT/expected-trace"
	cmp "$TEST_ROOT/expected-trace" "$CONSUMER_TRACE"
done
printf '%s\n' 'ok - manifest-only requirement edit blocks all uncommissioned consumer variants'
