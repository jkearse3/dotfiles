#!/usr/bin/env bash

set -euo pipefail

token_count=$1
case_name=$2
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

case "$case_name" in
stdin-equivalence)
	printf 'Agent rules may mention <|endoftext|> as ordinary text.\n' >"$workdir/input.md"
	file_output=$($token_count --json "$workdir/input.md")
	stdin_output=$($token_count --json - <"$workdir/input.md")
	python3 - "$file_output" "$stdin_output" <<'PY'
import json
import sys

file_count = json.loads(sys.argv[1])["total"]
stdin_count = json.loads(sys.argv[2])["total"]
assert file_count == stdin_count
PY
	;;
multiple-inputs)
	printf 'first\n' >"$workdir/first.md"
	printf 'second input\n' >"$workdir/second.md"
	output=$($token_count --json "$workdir/first.md" "$workdir/second.md")
	python3 - "$output" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert len(result["inputs"]) == 2
assert result["total"] == sum(item["count"] for item in result["inputs"])
PY
	;;
json-output)
	printf 'structured output\n' >"$workdir/input.md"
	output=$($token_count --json "$workdir/input.md")
	python3 - "$output" "$workdir/input.md" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["encoding"] == "o200k_base"
assert result["inputs"][0]["name"] == sys.argv[2]
assert isinstance(result["inputs"][0]["count"], int)
assert result["total"] == result["inputs"][0]["count"]
PY
	;;
error-cases)
	expect_error() {
		local expected=$1
		shift
		if "$token_count" "$@" >"$workdir/stdout" 2>"$workdir/stderr"; then
			printf 'expected command to fail\n' >&2
			exit 1
		fi
		test ! -s "$workdir/stdout"
		grep -Fq "$expected" "$workdir/stderr"
	}

	expect_error 'the following arguments are required' </dev/null
	expect_error 'No such file or directory' "$workdir/missing.md"
	printf '\377' >"$workdir/invalid.md"
	expect_error 'codec can' "$workdir/invalid.md"
	expect_error 'standard input (-) may be specified at most once' - - </dev/null
	;;
*)
	printf 'unknown test case: %s\n' "$case_name" >&2
	exit 2
	;;
esac
