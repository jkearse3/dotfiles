#!/usr/bin/env bash
# Fixtures for `space-new.sh`, run as a build gate by the derivation in
# `default.nix`. Takes the picker executable under test and the real `fd` it
# runs with. Each fixture runs the picker in a scratch home with a fake fzf,
# which records the folders it was offered and answers with a set pick (or
# the first folder offered) and exit status, and a fake herdr-app, which records its arguments, so no
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
		'if [[ $FAKE_FZF_PICK == @first ]]; then head -n 1 "$offered"' \
		'elif [[ -n $FAKE_FZF_PICK ]]; then printf "%s\n" "$FAKE_FZF_PICK"; fi' \
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

# Runs the picker in the scratch home with CURRENT as the folder offered
# first, the fake fzf answering PICK (`@first`: the first folder offered)
# and exiting FZF_STATUS, and the fake herdr-app exiting APP_STATUS, starting
# a fresh call log. Standard input is empty, so a held error ends at once.
run_picker() {
	local current=$1 pick=$2 fzf_status=$3 app_status=$4

	rm -f "$offered" "$app_calls"
	HOME=$home XDG_CONFIG_HOME="$home/.config" FAKE_FZF_PICK=$pick FAKE_FZF_STATUS=$fzf_status FAKE_APP_STATUS=$app_status \
		"$picker" "$fd" "$fzf" "$herdr_app" "$current" </dev/null 2>"$work/stderr"
}

# Fails with LABEL unless the only app call made an unnamed space in FOLDER.
expect_space_in() {
	local label=$1 folder=$2

	[[ -e $app_calls && $(<"$app_calls") == $'4\ndo\nspace.new\n--folder\n'"$folder" ]] ||
		fail "$label: expected one unnamed space.new in $folder, got: $(<"$app_calls")"
}

home_folders=$'a/\na/Library/\na/go/\na/go/z/\nb c/\nb c/d/'

run_picker "$home/a" "b c/d/" 0 0 || fail "pick: exited nonzero: $(<"$work/stderr")"
[[ $(head -n 1 "$offered") == a/ ]] ||
	fail "pick: expected the current folder first, got: $(<"$offered")"
[[ $(sort "$offered") == "$home_folders" ]] ||
	fail "pick: expected every folder but hidden ones, ~/go and ~/Library, once each, got: $(<"$offered")"
expect_space_in pick "$home/b c/d"

run_picker "$home/b c/d/" @first 0 0 || fail "enter: exited nonzero: $(<"$work/stderr")"
[[ $(head -n 1 "$offered") == "b c/d/" && $(grep -c '^b c/d/$' "$offered") == 1 ]] ||
	fail "enter: expected the current folder first and once, got: $(<"$offered")"
expect_space_in enter "$home/b c/d"

run_picker "$home" @first 0 0 || fail "home: exited nonzero: $(<"$work/stderr")"
[[ $(head -n 1 "$offered") == "$home/" && $(tail -n +2 "$offered" | sort) == "$home_folders" ]] ||
	fail "home: expected home first, then every folder, got: $(<"$offered")"
expect_space_in home "$home"

mkdir -p "$work/elsewhere"
run_picker "$work/elsewhere" @first 0 0 || fail "outside home: exited nonzero: $(<"$work/stderr")"
[[ $(head -n 1 "$offered") == "$work/elsewhere/" && $(tail -n +2 "$offered" | sort) == "$home_folders" ]] ||
	fail "outside home: expected the absolute folder first, then every folder, got: $(<"$offered")"
expect_space_in "outside home" "$work/elsewhere"

run_picker / @first 0 0 || fail "root: exited nonzero: $(<"$work/stderr")"
[[ $(head -n 1 "$offered") == / ]] || fail "root: expected / first, got: $(<"$offered")"
expect_space_in root /

if run_picker a @first 0 0; then
	fail "relative current: exited 0"
fi
[[ ! -e $app_calls ]] || fail "relative current: made a space: $(<"$app_calls")"

for status in 1 130; do
	run_picker "$home" "" "$status" 0 || fail "fzf exit $status: exited nonzero"
	[[ ! -e $app_calls ]] || fail "fzf exit $status: made a space: $(<"$app_calls")"
done

if run_picker "$home" "" 2 0; then
	fail "fzf error: exited 0"
fi
[[ ! -e $app_calls ]] || fail "fzf error: made a space: $(<"$app_calls")"

if run_picker "$home" "a/" 0 1; then
	fail "app failure: exited 0"
fi
grep -q 'no window' "$work/stderr" || fail "app failure: error not shown: $(<"$work/stderr")"

echo "space-new fixtures passed"
