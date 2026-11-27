#!/usr/bin/env bash

# Runs the signing program, built around a stand-in ssh-keygen that records
# its arguments, environment, and stdin in SIGNER_TEST_RECORD, as git and jj
# call it. Usage: test.sh <signing program>.

set -euo pipefail

signer=$1
record=$(mktemp -d)
trap 'rm -rf "$record"' EXIT
export SIGNER_TEST_RECORD=$record

fail() {
	echo "not ok - $*" >&2
	exit 1
}

# jj: data on stdin, signature on stdout.
printf 'commit data\n' | SSH_AUTH_SOCK=/agent.sock SSH_ASKPASS=/askpass SSH_ASKPASS_REQUIRE=force \
	"$signer" -Y sign -f /home/test/.ssh/git_secure_enclave -n git >"$record/stdout" 2>"$record/stderr"
[ "$(cat "$record/args")" = "-Y sign -f /home/test/.ssh/git_secure_enclave -n git" ] || fail "arguments: $(cat "$record/args")"
[ "$(cat "$record/stdin")" = "commit data" ] || fail "stdin was not passed through"
[ "$(cat "$record/stdout")" = "SIGNATURE" ] || fail "stdout holds more than ssh-keygen's output: $(cat "$record/stdout")"
grep -qx 'SSH_AUTH_SOCK=<unset>' "$record/env" || fail "SSH_AUTH_SOCK reached ssh-keygen"
grep -qx 'SSH_ASKPASS=<unset>' "$record/env" || fail "SSH_ASKPASS reached ssh-keygen"
grep -qx 'SSH_ASKPASS_REQUIRE=never' "$record/env" || fail "askpass not disabled"
grep -qx 'SSH_SK_PROVIDER=/usr/lib/ssh-keychain.dylib' "$record/env" || fail "Secure Enclave provider not set"
grep -q 'stand-in notice' "$record/stderr" || fail "stderr was not passed through"
echo "ok - jj's call signs with the Secure Enclave provider and no 1Password agent"

# git: data in a file, arguments in another order, exit status passed back.
: >"$record/fail"
status=0
"$signer" -Y sign -n git -f /home/test/.ssh/git_secure_enclave /tmp/data </dev/null >/dev/null 2>&1 || status=$?
[ "$status" = 3 ] || fail "exit status $status, expected ssh-keygen's 3"
[ "$(cat "$record/args")" = "-Y sign -n git -f /home/test/.ssh/git_secure_enclave /tmp/data" ] || fail "arguments: $(cat "$record/args")"
echo "ok - git's call passes its arguments and ssh-keygen's exit status"
