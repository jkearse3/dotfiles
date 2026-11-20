#!/usr/bin/env bash

set -euo pipefail

command -v agent-store >/dev/null 2>&1 || {
	printf 'not ok - agent-store is required on PATH\n' >&2
	exit 1
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PREPARE_PATH="$SCRIPT_DIR/../scripts/prepare-path.sh"
TMPDIR_ROOT=$(mktemp -d)
TMPDIR_ROOT=$(cd "$TMPDIR_ROOT" && pwd -P)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# The preparer is invoked by its absolute path with an explicit --workspace, so
# run the suite from a directory unrelated to any fixture to prove it never
# derives its target from the caller's working directory. Store resolution and
# its guarantees are agent-store's and tested with it.
OUTSIDE="$TMPDIR_ROOT/outside cwd"
mkdir -p "$OUTSIDE"
cd "$OUTSIDE"

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

assert_eq() {
	local expected=$1
	local actual=$2
	local description=$3

	[[ $actual == "$expected" ]] || fail "$description: expected '$expected', got '$actual'"
	printf 'ok - %s\n' "$description"
}

assert_status() {
	local expected=$1
	local actual=$2
	local description=$3

	[[ $actual -eq $expected ]] || fail "$description: expected status $expected, got $actual"
	printf 'ok - %s\n' "$description"
}

main="$TMPDIR_ROOT/main repo"
linked="$TMPDIR_ROOT/linked repo"
git init -q "$main"
git -C "$main" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m initial
git -C "$main" worktree add -q --detach "$linked"

prepared_path=$(SPEC_TIMESTAMP=2026-01-02-030405 "$PREPARE_PATH" --workspace "$linked" 'Fast Spec!')
assert_eq "$main/.agent/specs/2026-01-02-030405-fast-spec.md" "$prepared_path" 'spec path joins canonical storage, timestamp, and normalized slug'
[[ -f $prepared_path ]] || fail 'spec path is reserved atomically'
printf '%s\n' 'ok - spec path is reserved atomically'
git -C "$main" check-ignore -q .agent/specs/example.md || fail 'spec artifacts are ignored'
printf '%s\n' 'ok - spec artifacts are ignored'

collision_path=$(SPEC_TIMESTAMP=2026-01-02-030405 "$PREPARE_PATH" --workspace "$linked" 'Fast Spec!')
assert_eq "$main/.agent/specs/2026-01-02-030405-fast-spec-2.md" "$collision_path" 'spec path avoids collisions'

# A repository is targeted only through --workspace; the caller's cwd (here a
# different Git repository) must not influence the store.
repo_b="$TMPDIR_ROOT/repo b"
git init -q "$repo_b"
git -C "$repo_b" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m initial
iso_prepared=$(cd "$main" && SPEC_TIMESTAMP=2026-01-02-030405 "$PREPARE_PATH" --workspace "$repo_b" cross)
assert_eq "$repo_b/.agent/specs" "$(dirname "$iso_prepared")" 'preparer stores under the --workspace repository, not the caller cwd'

# prepare-path.sh validates its own CLI shape before invoking agent-store.
set +e
prep_missing_out=$("$PREPARE_PATH" 2>/dev/null)
prep_missing_status=$?
set -e
assert_status 2 "$prep_missing_status" 'preparer rejects a missing --workspace'
assert_eq '' "$prep_missing_out" 'preparer missing --workspace prints no stdout'

set +e
"$PREPARE_PATH" --workspace >/dev/null 2>&1
prep_novalue_status=$?
set -e
assert_status 2 "$prep_novalue_status" 'preparer rejects --workspace without a value'

set +e
"$PREPARE_PATH" --bogus "$main" >/dev/null 2>&1
prep_unknown_status=$?
set -e
assert_status 2 "$prep_unknown_status" 'preparer rejects an unknown option'

set +e
"$PREPARE_PATH" --workspace "$main" slug extra >/dev/null 2>&1
prep_extra_status=$?
set -e
assert_status 2 "$prep_extra_status" 'preparer rejects extra arguments'

# agent-store failures propagate through the preparer with empty stdout.
set +e
prep_missing_ws_out=$("$PREPARE_PATH" --workspace "$TMPDIR_ROOT/does not exist" slug 2>/dev/null)
prep_missing_ws_status=$?
set -e
assert_status 1 "$prep_missing_ws_status" 'preparer propagates a nonexistent workspace failure'
assert_eq '' "$prep_missing_ws_out" 'preparer nonexistent workspace prints no stdout'

tracked="$TMPDIR_ROOT/tracked store"
git init -q "$tracked"
mkdir -p "$tracked/.agent/specs"
printf '%s\n' tracked >"$tracked/.agent/specs/existing.md"
git -C "$tracked" add .agent/specs/existing.md
git -C "$tracked" -c user.name=Test -c user.email=test@example.com commit -qm tracked
set +e
"$PREPARE_PATH" --workspace "$tracked" rejected >/dev/null 2>&1
tracked_status=$?
set -e
assert_status 1 "$tracked_status" 'preparer propagates a tracked spec store failure'

set +e
SPEC_TIMESTAMP=../escape "$PREPARE_PATH" --workspace "$linked" rejected >/dev/null 2>&1
timestamp_status=$?
set -e
assert_status 1 "$timestamp_status" 'invalid spec timestamp is rejected'
rejected_files=$(find "$main/.agent" -name '*rejected*' -print)
assert_eq '' "$rejected_files" 'invalid spec timestamp creates no file'
