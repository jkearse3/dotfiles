#!/usr/bin/env bash

set -euo pipefail

denied=$1
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

expect_denied() {
	local program=$1
	local interaction=$2
	shift 2

	local status=0
	"$denied" "$program" "$interaction" "$@" >"$workdir/stdout" 2>"$workdir/stderr" || status=$?
	[[ $status -eq 1 ]]
	[[ ! -s "$workdir/stdout" ]]
	grep -Fq "blocked $program $interaction in a coding-agent session" "$workdir/stderr"
}

expect_denied jj editor "$workdir/description with spaces"
expect_denied jj diff-editor "$workdir/left" "$workdir/right"
expect_denied jj merge-editor "$workdir/base" "$workdir/left" "$workdir/right" "$workdir/output"
expect_denied git editor "$workdir/COMMIT_EDITMSG"
expect_denied git sequence-editor "$workdir/git-rebase-todo"
expect_denied git askpass 'Password for https://user@example.invalid:'
expect_denied ssh askpass 'Enter passphrase for key with credential-looking text: secret'

status=0
"$denied" unknown context ignored >"$workdir/stdout" 2>"$workdir/stderr" || status=$?
[[ $status -eq 2 ]]
[[ ! -s "$workdir/stdout" ]]
grep -Fq 'unsupported context' "$workdir/stderr"
