#!/usr/bin/env bash
# Fixtures for `space-new.sh`, run as a build gate by the derivation in
# `default.nix`. Takes the picker executable under test and the real `fd` it
# runs with. Each fixture runs the picker in a scratch home with a fake fzf,
# which records the folders it was offered and answers with a set pick and
# exit status, and a fake herdr-app, which records its arguments, so no
# space is made for real.
set -euo pipefail
export LC_ALL=C

usage='usage: space-new-test.sh <herdr-space-new-picker> <fd>'
picker=${1:?$usage}
fd=${2:?$usage}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
	echo "FAIL: $1" >&2
	exit 1
}

home="$work/home"
mkdir -p "$home/go/x" "$home/Library/y" "$home/a/go/z" "$home/a/Library" "$home/b c/d" "$home/.hidden/e"

offered="$work/offered"
app_calls="$work/app-calls"
fzf="$work/fzf"
herdr_app="$work/herdr-app"
{
	printf '#!%s\n' "$BASH"
	printf 'offered=%q\n' "$offered"
	# shellcheck disable=SC2016 # Expanded by the fake, not here.
	printf '%s\n' \
		'tr "\0" "\n" >"$offered"' \
		'if [[ -n $FAKE_FZF_PICK ]]; then printf "%s\n" "$FAKE_FZF_PICK"; fi' \
		'exit "$FAKE_FZF_STATUS"'
} >"$fzf"
{
	printf '#!%s\n' "$BASH"
	printf 'app_calls=%q\n' "$app_calls"
	# shellcheck disable=SC2016 # Expanded by the fake, not here.
	printf '%s\n' \
		'printf "%s\n" "$#" "$@" >>"$app_calls"' \
		'if [[ $FAKE_APP_STATUS != 0 ]]; then echo "{\"error\": \"no window\"}"; fi' \
		'exit "$FAKE_APP_STATUS"'
} >"$herdr_app"
chmod +x "$fzf" "$herdr_app"

# Runs the picker in the scratch home with the fake fzf answering PICK and
# exiting FZF_STATUS, and the fake herdr-app exiting APP_STATUS, starting a
# fresh call log. Standard input is empty, so a held error ends at once.
run_picker() {
	local pick=$1 fzf_status=$2 app_status=$3

	rm -f "$offered" "$app_calls"
	HOME=$home XDG_CONFIG_HOME="$home/.config" FAKE_FZF_PICK=$pick FAKE_FZF_STATUS=$fzf_status FAKE_APP_STATUS=$app_status \
		"$picker" "$fd" "$fzf" "$herdr_app" </dev/null 2>"$work/stderr"
}

run_picker "b c/d/" 0 0 || fail "pick: exited nonzero: $(<"$work/stderr")"
[[ $(sort "$offered") == $'a/\na/Library/\na/go/\na/go/z/\nb c/\nb c/d/' ]] ||
	fail "pick: expected every folder but hidden ones, ~/go and ~/Library, got: $(<"$offered")"
[[ $(<"$app_calls") == $'4\ndo\nspace.new\n--folder\n'"$home/b c/d" ]] ||
	fail "pick: expected one unnamed space.new for the pick, got: $(<"$app_calls")"

for status in 1 130; do
	run_picker "" "$status" 0 || fail "fzf exit $status: exited nonzero"
	[[ ! -e $app_calls ]] || fail "fzf exit $status: made a space: $(<"$app_calls")"
done

if run_picker "" 2 0; then
	fail "fzf error: exited 0"
fi
[[ ! -e $app_calls ]] || fail "fzf error: made a space: $(<"$app_calls")"

if run_picker "a/" 0 1; then
	fail "app failure: exited 0"
fi
grep -q 'no window' "$work/stderr" || fail "app failure: error not shown: $(<"$work/stderr")"

echo "space-new fixtures passed"
