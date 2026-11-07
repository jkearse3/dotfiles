#!/usr/bin/env bash
# Fixtures for `install-bundle.sh`, run as a build gate by the derivation in
# `default.nix`. Takes the installer executable under test as its only
# argument. Each fixture installs a fake read-only bundle into a scratch
# Applications folder with fake `lsregister` and `codesign` that log their
# calls, so nothing is signed or registered for real.
set -euo pipefail

install=${1:?usage: install-bundle-test.sh <herdr-app-install-bundle>}

work=$(mktemp -d)
trap 'chmod -R u+w "$work"; rm -rf "$work"' EXIT

fail() {
	echo "FAIL: $1" >&2
	exit 1
}

# Creates a read-only bundle at PATH whose executable holds CONTENT, as a
# bundle in the Nix store is.
fake_bundle() {
	local path=$1 content=$2

	mkdir -p "$path/Contents/MacOS" "$path/Contents/Resources"
	printf '%s\n' "$content" >"$path/Contents/MacOS/Herdr"
	chmod -R a-w "$path"
}

# Creates a tool at PATH that appends its arguments to LOG and exits STATUS.
fake_tool() {
	local path=$1 log=$2 status=$3

	printf '#!%s\nprintf "%%s\\n" "$*" >>%q\nexit %d\n' "$BASH" "$log" "$status" >"$path"
	chmod +x "$path"
}

old_bundle="$work/store/aaaa-herdr-app-bundle/Applications/Herdr.app"
new_bundle="$work/store/bbbb-herdr-app-bundle/Applications/Herdr.app"
fake_bundle "$old_bundle" old
fake_bundle "$new_bundle" new

apps="$work/Applications"
dest="$apps/Herdr.app"
marker="$dest/Contents/Resources/dotfiles-source"
log="$work/calls"
lsregister="$work/lsregister"
codesign="$work/codesign"
failing_codesign="$work/failing-codesign"
fake_tool "$lsregister" "$log" 0
fake_tool "$codesign" "$log" 0
fake_tool "$failing_codesign" "$log" 1

# Runs the installer for SOURCE with the fake tools, starting a fresh log.
install_from() {
	local source=$1

	: >"$log"
	"$install" "$source" "$dest" "$lsregister" "${2:-$codesign}"
}

expect_installed_from() {
	local name=$1 source=$2 content=$3

	[[ -d $dest && ! -L $dest ]] || fail "$name: $dest is not a real directory"
	[[ $(<"$dest/Contents/MacOS/Herdr") == "$content" ]] || fail "$name: executable is not from $source"
	[[ $(<"$marker") == "$source" ]] || fail "$name: marker does not name $source"
	[[ -w $dest/Contents/MacOS/Herdr ]] || fail "$name: copy is still read-only"
	[[ $(<"$log") == "--force --sign - $dest"$'\n'"-f $dest" ]] || fail "$name: expected sign then register, got: $(<"$log")"
}

# An unrelated entry beside the bundle must survive every fixture.
mkdir -p "$apps/Other.app"
printf 'other\n' >"$apps/Other.app/keep"

install_from "$old_bundle"
expect_installed_from "missing bundle" "$old_bundle" old

before=$(stat -c '%i %Y' "$dest" "$dest/Contents/MacOS/Herdr")
install_from "$old_bundle"
[ ! -s "$log" ] || fail "unchanged source: expected no sign or register, got: $(<"$log")"
[[ $(stat -c '%i %Y' "$dest" "$dest/Contents/MacOS/Herdr") == "$before" ]] || fail "unchanged source: bundle was touched"

printf 'stale\n' >"$dest/Contents/MacOS/stale"
install_from "$new_bundle"
expect_installed_from "changed source" "$new_bundle" new
[[ ! -e $dest/Contents/MacOS/stale ]] || fail "changed source: old bundle contents remain"

rm -f "$marker"
install_from "$new_bundle"
expect_installed_from "bundle without a marker" "$new_bundle" new

chmod -R u+w "$dest"
rm -rf "$dest"
ln -s "$old_bundle" "$dest"
install_from "$new_bundle"
expect_installed_from "symlinked bundle" "$new_bundle" new
[[ $(<"$old_bundle/Contents/MacOS/Herdr") == old && ! -w $old_bundle/Contents/MacOS/Herdr ]] ||
	fail "symlinked bundle: link target was changed"

if install_from "$old_bundle" "$failing_codesign" 2>/dev/null; then
	fail "failing codesign: expected a nonzero exit"
fi
[[ ! -e $marker ]] || fail "failing codesign: marker remains, so the next switch would skip the bundle"
install_from "$old_bundle"
expect_installed_from "retry after a failure" "$old_bundle" old

[[ $(<"$apps/Other.app/keep") == other ]] || fail "unrelated entry was changed"
[[ $(find "$apps" -mindepth 1 -maxdepth 1 | sort) == "$apps/Herdr.app"$'\n'"$apps/Other.app" ]] ||
	fail "unexpected entries: $(find "$apps" -mindepth 1 -maxdepth 1)"

echo "install-bundle fixtures passed"
