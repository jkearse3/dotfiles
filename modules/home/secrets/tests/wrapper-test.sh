#!/usr/bin/env bash
# Exercise generated wrappers, not a copy of their shell implementation.
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
	rm -f "$TEST_ROOT/started" "$TEST_ROOT/selectors"
	"$@" >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr" || actual=$?
	[[ $actual == "$expected" ]] || fail "expected status $expected, got $actual"
}

for listing in '' 'No provider aliases configured.' '  unrelated = dotenv://test' \
	'  notdotfiles = dotenv://test' '  dotfiles-extra = dotenv://test' \
	'description mentions dotfiles = dotenv://test'; do
	export PROVIDER_LIST="$listing"
	run_status 23 env CHILD_STATUS=23 "$OPTIONAL_WRAPPER" '' 'two words' '--flag'
	[[ -f $TEST_ROOT/started && ! -e $TEST_ROOT/selectors ]] || fail 'missing-alias fallback'
	grep -qxF ADMITTED=ambient "$TEST_ROOT/environment"
	grep -qxF UNRELATED=preserved "$TEST_ROOT/environment"
	if grep -qE '^(EXCLUDED|OTHER_PROFILE)=' "$TEST_ROOT/environment"; then fail 'excluded inherited secret'; fi
	printf '%s\0' '' 'two words' '--flag' >"$TEST_ROOT/expected-argv"
	cmp "$TEST_ROOT/expected-argv" "$TEST_ROOT/argv"
	run_status 1 "$REQUIRED_WRAPPER"
	[[ ! -e $TEST_ROOT/started ]] || fail 'required scope launched'
	grep -qF 'not commissioned' "$TEST_ROOT/stderr"
done
printf '%s\n' 'ok - absent and misleading aliases use filtered fallback; required policy fails'

run_status 1 env INSPECT_STATUS=9 "$OPTIONAL_WRAPPER"
grep -qF 'failed to inspect' "$TEST_ROOT/stderr"
[[ ! -e $TEST_ROOT/started ]] || fail 'inspection error launched child'

for listing in '  dotfiles = dotenv://fixture' $'\t dotfiles\t= dotenv://fixture'; do
	export PROVIDER_LIST="$listing"
	run_status 37 "$OPTIONAL_WRAPPER" '' 'two words'
	[[ ! -e $TEST_ROOT/started ]] || fail 'configured provider error fell back'
	printf '%s\n' run --file >"$TEST_ROOT/expected-selectors"
	head -n 2 "$TEST_ROOT/selectors" >"$TEST_ROOT/actual-selectors"
	cmp "$TEST_ROOT/expected-selectors" "$TEST_ROOT/actual-selectors"
	tail -n +4 "$TEST_ROOT/selectors" >"$TEST_ROOT/actual-selectors"
	printf '%s\n' --provider dotfiles --profile default --scope optional -- >"$TEST_ROOT/expected-selectors"
	head -n 7 "$TEST_ROOT/actual-selectors" >"$TEST_ROOT/selector-prefix"
	cmp "$TEST_ROOT/expected-selectors" "$TEST_ROOT/selector-prefix"
done

run_status 37 env INSPECT_STATUS=9 SECRETSPEC_PROVIDER=dotenv://override \
	SECRETSPEC_FILE=/wrong SECRETSPEC_PROFILE=wrong SECRETSPEC_SCOPE=wrong "$OPTIONAL_WRAPPER"
grep -qxF dotenv://override "$TEST_ROOT/selectors"
grep -qxF default "$TEST_ROOT/selectors"
grep -qxF optional "$TEST_ROOT/selectors"
if grep -qxF /wrong "$TEST_ROOT/selectors"; then fail 'ambient file replaced fixed manifest'; fi
run_status 1 env INSPECT_STATUS=9 SECRETSPEC_PROVIDER= "$OPTIONAL_WRAPPER"
printf '%s\n' 'ok - inspection failures, configured errors, overrides and fixed selectors'
