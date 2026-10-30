#!/usr/bin/env bash
# Real SecretSpec with disposable dotenv providers; never use user configuration.
set -euo pipefail
mkdir -p "$TEST_ROOT"
export HOME="$TEST_ROOT/home" XDG_CONFIG_HOME="$TEST_ROOT/config"
export XDG_DATA_HOME="$TEST_ROOT/data" XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
export ADMITTED=ambient EXCLUDED=excluded OTHER_PROFILE=excluded UNRELATED=preserved

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
run_status() {
	local expected=$1 actual=0
	shift
	rm -f "$TEST_ROOT/started"
	"$@" >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr" || actual=$?
	[[ $actual == "$expected" ]] || {
		cat "$TEST_ROOT/stderr" >&2
		fail "expected status $expected, got $actual"
	}
}
assert_boundary() {
	grep -qxF UNRELATED=preserved "$TEST_ROOT/environment"
	if grep -qE '^(EXCLUDED|OTHER_PROFILE)=' "$TEST_ROOT/environment"; then fail 'scope filtering'; fi
}

# Capture actual presentation output and exercise discovery with that output.
secretspec config global provider list >"$TEST_ROOT/empty-list"
run_status 0 "$REAL_WRAPPER"
grep -qxF ADMITTED=ambient "$TEST_ROOT/environment"
assert_boundary

printf 'ADMITTED=stored\nEXCLUDED=not-admitted\n' >"$TEST_ROOT/local.env"
secretspec config global provider add dotfiles "dotenv://$TEST_ROOT/local.env"
secretspec config global provider list >"$TEST_ROOT/provider-list"
grep -qE '^[[:space:]]*dotfiles[[:space:]]*=' "$TEST_ROOT/provider-list"
run_status 23 env CHILD_STATUS=23 "$REAL_WRAPPER" '' 'two words'
grep -qxF ADMITTED=stored "$TEST_ROOT/environment"
assert_boundary
printf '%s\0' '' 'two words' >"$TEST_ROOT/expected-argv"
cmp "$TEST_ROOT/expected-argv" "$TEST_ROOT/argv"

: >"$TEST_ROOT/local.env"
run_status 0 "$REAL_WRAPPER"
grep -qxF ADMITTED=ambient "$TEST_ROOT/environment"
assert_boundary
printf '%s\n' 'ok - real SecretSpec scoped filtering, provider precedence and ambient fallback'

# Invalid UTF-8 is a provider read error, not an absent optional value.
printf '\377\376\n' >"$TEST_ROOT/broken.env"
secretspec config global provider add dotfiles "dotenv://$TEST_ROOT/broken.env"
run_status 1 "$REAL_WRAPPER"
[[ ! -e $TEST_ROOT/started ]] || fail 'optional configured-provider failure started child'
grep -qF 'valid UTF-8' "$TEST_ROOT/stderr"
run_status 1 env SECRETSPEC_PROVIDER="dotenv://$TEST_ROOT/broken.env" "$REAL_WRAPPER"
[[ ! -e $TEST_ROOT/started ]] || fail 'optional explicit-provider failure started child'
printf '%s\n' 'ok - real SecretSpec optional provider read errors fail without anonymous retry'
