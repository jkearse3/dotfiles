#!/usr/bin/env bash

# Tests bootstrap/git_key.py against stand-ins for sc_auth and ssh-keygen
# (stubs/), whose output reproduces what the real tools printed for a
# throwaway key (fixtures/). Usage: git-key-test.sh <python3> <git_key.py>
# <stubs> <fixtures> <handle path relative to the home directory>. The script
# runs as bootstrap/git-key.sh runs it, under `python3 -I`, with an empty
# environment apart from HOME and TMPDIR in a temporary directory and the
# variables below.

set -euo pipefail

python=$1
script=$2
stubs=$3
fixtures=$4
handle_relative=$5

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
state=$work/state
mkdir -p "$state" "$work/tmp"
export GIT_KEY_TEST_STATE=$state
export GIT_KEY_TEST_FIXTURES=$fixtures

fail() {
	echo "not ok - $*" >&2
	echo "--- stdout" >&2
	cat "$work/stdout" >&2 || true
	echo "--- stderr" >&2
	cat "$work/stderr" >&2 || true
	exit 1
}

ok() {
	echo "ok - $*"
}

# A fresh home for each scenario, without ~/.ssh.
fresh_home() {
	rm -rf "${work:?}/home"
	mkdir "$work/home"
	: >"$state/identities"
	rm -f "$state/locked" "$state/stuck" "$state/wrong-key" "$state/list-fails" "$state/create-fails"
}

# Runs the script with arguments $2... and checks that it exits with $1.
expect() {
	local expected=$1 status=0
	shift
	: >"$state/log"
	env -i HOME="$work/home" TMPDIR="${tmpdir:-$work/tmp}" USER=test \
		GIT_KEY_TEST_STUBS="$stubs" GIT_KEY_TEST_STATE="$state" GIT_KEY_TEST_FIXTURES="$fixtures" \
		GIT_KEY_TEST_EXPORT_SECONDS="${export_seconds:-30}" SSH_AUTH_SOCK=/should/not/be/used \
		SSH_ASKPASS=/should/not/be/used \
		"$python" -I "$script" "$@" >"$work/stdout" 2>"$work/stderr" </dev/null || status=$?
	[ "$status" = "$expected" ] || fail "git_key.py $* exited $status, expected $expected"
	[ -z "$(ls -A "$work/tmp")" ] || fail "git_key.py $* left temporary files: $(ls -A "$work/tmp")"
}

contains() {
	grep -qF -- "$2" "$work/$1" 2>/dev/null || grep -qF -- "$2" "$state/$1" 2>/dev/null || fail "$1 lacks: $2"
}

# Checks that a failure wrote exactly one line, its git-key: cause, to stderr.
one_line_stderr() {
	if [ "$(wc -l <"$work/stderr")" -ne 1 ] || ! grep -q '^git-key: ' "$work/stderr"; then
		fail "stderr is not one git-key: line"
	fi
}

lacks() {
	if grep -qF -- "$2" "$work/$1" 2>/dev/null || grep -qF -- "$2" "$state/$1" 2>/dev/null; then
		fail "$1 unexpectedly contains: $2"
	fi
}

handle=$work/home/$handle_relative
key1=$(cut -d' ' -f1,2 "$fixtures/key1.pub")

# The stand-in sc_auth prints exactly what the real one printed for the
# fixture identity, which was captured under an earlier label, git-personal;
# the label only fills its column.
fresh_home
echo "git-personal|F7D94CA2A0F18E471C38856CD5BAF175A5EBAB96|$fixtures/key1.pub|Git - Fixture Mac - Secure Enclave" >"$state/identities"
PATH=$stubs:$PATH sc_auth list-ctk-identities | cmp -s - "$fixtures/sc_auth-list.txt" || fail "stand-in sc_auth table differs from fixtures/sc_auth-list.txt"
PATH=$stubs:$PATH sc_auth list-ctk-identities -t ssh | cmp -s - "$fixtures/sc_auth-list-ssh.txt" || fail "stand-in sc_auth -t ssh table differs from fixtures/sc_auth-list-ssh.txt"
: >"$state/identities"
PATH=$stubs:$PATH sc_auth list-ctk-identities | cmp -s - "$fixtures/sc_auth-list-empty.txt" || fail "stand-in sc_auth empty table differs"
ok "the stand-in sc_auth reproduces the real tables"

fresh_home
expect 1 --frobnicate
contains stderr "git-key: unknown argument --frobnicate; see bootstrap/git-key.sh --help"
one_line_stderr
lacks log "create-ctk-identity"
ok "an unknown argument is refused in one line before anything is created"

fresh_home
expect 1 --name "Personal Laptop"
contains stderr "git-key: unknown argument --name; see bootstrap/git-key.sh --help"
one_line_stderr
lacks log "create-ctk-identity"
ok "the earlier --name is refused like any other argument"

fresh_home
touch "$state/locked"
expect 1
contains stderr "unlock the screen and rerun"
contains stderr "delete the identity (sc_auth delete-ctk-identity -h F7D94CA2A0F18E471C38856CD5BAF175A5EBAB96) and rerun"
lacks stderr "--name"
one_line_stderr
contains log "sc_auth create-ctk-identity -l git -k p-256-ne -t none"
[ ! -e "$work/home/.ssh" ] || fail "a failed export created ~/.ssh"
rm "$state/locked"
ok "a failed export installs nothing and says how to recover"

expect 0
contains log "ssh-keygen -w /usr/lib/ssh-keychain.dylib -K -N "
lacks log "create-ctk-identity"
[ "$(/usr/bin/stat -f %Lp "$work/home/.ssh")" = 700 ] || fail ".ssh directory mode"
[ "$(/usr/bin/stat -f %Lp "$handle")" = 600 ] || fail "handle mode"
[ "$(/usr/bin/stat -f %Lp "$handle.pub")" = 644 ] || fail "handle .pub mode"
[ "$(cat "$handle")" = "stand-in handle for $fixtures/key1.pub" ] || fail "installed the wrong handle"
contains stdout "  $key1"
contains stdout "https://github.com/settings/ssh/new"
contains stdout "twice, once as an"
contains stdout "Authentication Key and once as a Signing Key, each with a title you choose"
contains stdout "export GIT_SSH_COMMAND=\"ssh -i $handle -o IdentitiesOnly=yes -o IdentityAgent=none -o SecurityKeyProvider=/usr/lib/ssh-keychain.dylib\""
[ ! -s "$work/stderr" ] || fail "success wrote to stderr"
ok "a rerun reuses the identity, creates ~/.ssh, installs the handle, and prints the key and how to add it"

touch "$state/locked"
expect 0
lacks log "-K"
contains stdout "  $key1"
rm "$state/locked"
ok "a rerun with a matching handle prints without exporting, so a locked screen does not matter"

cp "$fixtures/key2.pub" "$handle.pub"
echo "old handle" >"$handle"
expect 0
contains log "-K"
[ "$(cat "$handle")" = "stand-in handle for $fixtures/key1.pub" ] || fail "did not replace a stale handle"
ok "a stale handle is replaced by a fresh export"

cp "$fixtures/key2.pub" "$handle.pub"
echo "old handle" >"$handle"
touch "$state/wrong-key"
expect 1
contains stderr "the exported key does not match the git identity"
contains stderr "Delete the identity (sc_auth delete-ctk-identity -h F7D94CA2A0F18E471C38856CD5BAF175A5EBAB96) and rerun"
one_line_stderr
[ "$(cat "$handle")" = "old handle" ] || fail "a mismatched export replaced the handle"
rm "$state/wrong-key"
ok "an export of another key leaves the existing files"

touch "$state/stuck"
export_seconds=2
expect 1
unset export_seconds
contains stderr "unlock the screen and rerun"
one_line_stderr
[ "$(cat "$handle")" = "old handle" ] || fail "a stuck export replaced the handle"
if /usr/bin/pgrep -f "sleep 600" >/dev/null 2>&1; then
	/usr/bin/pkill -f "sleep 600" || true
	fail "a stuck export was left running"
fi
rm "$state/stuck"
ok "a stuck export is stopped"

fresh_home
echo "other-tool|ABCDEF|$fixtures/key2.pub|Other Tool" >"$state/identities"
expect 1
contains stderr "identities other than one labeled git, and"
one_line_stderr
lacks log "create-ctk-identity"
lacks log "-K"
ok "another identity is refused before anything is created"

fresh_home
echo "git-personal|ABCDEF|$fixtures/key2.pub|Git - Personal Laptop - Secure Enclave" >"$state/identities"
expect 1
contains stderr "identities other than one labeled git, and"
one_line_stderr
lacks log "create-ctk-identity"
ok "a key under the earlier git-personal label is refused like any other identity"

fresh_home
echo "git|AAAA|$fixtures/key1.pub|Git - One - Secure Enclave" >"$state/identities"
echo "git|BBBB|$fixtures/key2.pub|Git - Two - Secure Enclave" >>"$state/identities"
expect 1
contains stderr "identities other than one labeled git, and"
one_line_stderr
lacks log "-K"
ok "a second git-labeled identity is refused"

fresh_home
echo "git|F7D94CA2A0F18E471C38856CD5BAF175A5EBAB96|$fixtures/key1.pub|Git - Café Mac - Secure Enclave" >"$state/identities"
expect 0
lacks log "create-ctk-identity"
contains stdout "  $key1"
ok "a git identity with any Common Name, a non-ASCII one included, is reused"

fresh_home
touch "$state/list-fails"
expect 1
contains stderr "cannot list Secure Enclave identities (sc_auth: Error Domain=CryptoTokenKit Code=-25300 (stand-in list-ctk-identities failure)); make sc_auth list-ctk-identities work in this terminal, then rerun"
one_line_stderr
lacks log "create-ctk-identity"
ok "a failing sc_auth list is reported in one line with its error and a next step"

fresh_home
touch "$state/create-fails"
expect 1
contains stderr "cannot create the Secure Enclave identity (sc_auth: Error Domain=CryptoTokenKit Code=-25300 (stand-in create-ctk-identity failure)); fix what sc_auth reports, then rerun"
one_line_stderr
[ ! -s "$state/identities" ] || fail "a failed create left an identity"
[ ! -e "$work/home/.ssh" ] || fail "a failed create created ~/.ssh"
ok "a failing sc_auth create is reported in one line with its error and a next step"

fresh_home
: >"$work/tmp-file"
tmpdir=$work/tmp-file
expect 1
unset tmpdir
contains stderr "cannot create a temporary directory ($work/tmp-file/git-key."
contains stderr ": Not a directory); set TMPDIR to a writable directory, then rerun"
one_line_stderr
ok "a temporary directory that cannot be created is reported in one line with its error and a next step"

fresh_home
: >"$work/home/.ssh"
expect 1
contains stderr "cannot create $work/home/.ssh ($work/home/.ssh: File exists); make $work/home/.ssh a directory you can write to, then rerun"
one_line_stderr
ok "a file in place of ~/.ssh is reported in one line with its error and a next step"

fresh_home
mkdir -m 500 "$work/home/.ssh"
expect 1
chmod 700 "$work/home/.ssh"
contains stderr "cannot install the handle at $handle ($handle.pub.new: Permission denied); make $work/home/.ssh writable, then rerun"
one_line_stderr
[ ! -e "$handle" ] || fail "an unwritable ~/.ssh got a handle"
ok "an unwritable ~/.ssh is reported in one line with its error and a next step"

fresh_home
echo "git|F7D94CA2A0F18E471C38856CD5BAF175A5EBAB96|$fixtures/key1.pub|Git - Personal Laptop - Secure Enclave" >"$state/identities"
mkdir -m 000 "$work/home/.ssh"
expect 1
chmod 700 "$work/home/.ssh"
contains stderr "cannot install the handle at $handle ($handle.pub.new: Permission denied); make $work/home/.ssh writable, then rerun"
one_line_stderr
ok "a ~/.ssh that cannot be searched is reported in one line with its error and a next step"
