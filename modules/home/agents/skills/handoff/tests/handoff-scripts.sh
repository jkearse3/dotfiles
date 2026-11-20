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

prepared_path=$(HANDOFF_TIMESTAMP=2026-01-02-030405 "$PREPARE_PATH" --workspace "$linked" 'Fast Handoff!')
assert_eq "$main/.agent/handoffs" "$(dirname "$prepared_path")" 'handoff path uses canonical storage'
[[ $(basename "$prepared_path") == *-fast-handoff.md ]] || fail 'handoff path normalizes its slug'
[[ -f $prepared_path ]] || fail 'handoff path is reserved atomically'
printf '%s\n' 'ok - handoff path is reserved atomically'
git -C "$main" check-ignore -q .agent/handoffs/example.md || fail 'handoff artifacts are ignored'
printf '%s\n' 'ok - handoff artifacts are ignored'

collision_path=$(HANDOFF_TIMESTAMP=2026-01-02-030405 "$PREPARE_PATH" --workspace "$linked" 'Fast Handoff!')
[[ $collision_path == *-fast-handoff-2.md ]] || fail 'handoff path avoids collisions'
printf '%s\n' 'ok - handoff path avoids collisions'

# A repository is targeted only through --workspace; the caller's cwd (here a
# different Git repository) must not influence the store.
repo_b="$TMPDIR_ROOT/repo b"
git init -q "$repo_b"
git -C "$repo_b" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m initial
iso_prepared=$(cd "$main" && HANDOFF_TIMESTAMP=2026-01-02-030405 "$PREPARE_PATH" --workspace "$repo_b" cross)
assert_eq "$repo_b/.agent/handoffs" "$(dirname "$iso_prepared")" 'preparer stores under the --workspace repository, not the caller cwd'

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
mkdir -p "$tracked/.agent/handoffs"
printf '%s\n' tracked >"$tracked/.agent/handoffs/existing.md"
git -C "$tracked" add .agent/handoffs/existing.md
git -C "$tracked" -c user.name=Test -c user.email=test@example.com commit -qm tracked
set +e
"$PREPARE_PATH" --workspace "$tracked" rejected >/dev/null 2>&1
tracked_status=$?
set -e
assert_status 1 "$tracked_status" 'preparer propagates a tracked handoff store failure'

set +e
HANDOFF_TIMESTAMP=../escape "$PREPARE_PATH" --workspace "$linked" rejected >/dev/null 2>&1
timestamp_status=$?
set -e
assert_status 1 "$timestamp_status" 'invalid handoff timestamp is rejected'
