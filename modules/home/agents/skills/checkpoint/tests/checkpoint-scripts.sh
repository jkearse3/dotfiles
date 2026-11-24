#!/usr/bin/env bash

set -euo pipefail

command -v agent-store >/dev/null 2>&1 || {
	printf 'not ok - agent-store is required on PATH\n' >&2
	exit 1
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHECKPOINT="$SCRIPT_DIR/../scripts/checkpoint.sh"
TMPDIR_ROOT=$(mktemp -d)
TMPDIR_ROOT=$(cd "$TMPDIR_ROOT" && pwd -P)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# The script is invoked by its absolute path with explicit targets, so run the
# suite from a directory unrelated to any fixture to prove it never derives its
# target from the caller's working directory. Store resolution and its
# guarantees are agent-store's and tested with it.
OUTSIDE="$TMPDIR_ROOT/outside cwd"
mkdir -p "$OUTSIDE"
cd "$OUTSIDE"

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

pass() {
	printf 'ok - %s\n' "$1"
}

assert_eq() {
	local expected=$1
	local actual=$2
	local description=$3

	[[ $actual == "$expected" ]] || fail "$description: expected '$expected', got '$actual'"
	pass "$description"
}

# Runs the script expecting failure, and asserts its status and empty stdout.
assert_fails() {
	local expected_status=$1
	local description=$2
	shift 2
	local out status

	set +e
	out=$("$CHECKPOINT" "$@" 2>/dev/null)
	status=$?
	set -e
	[[ $status -eq $expected_status ]] ||
		fail "$description: expected status $expected_status, got $status"
	[[ -z $out ]] || fail "$description: expected no stdout, got '$out'"
	pass "$description"
}

main="$TMPDIR_ROOT/main repo"
linked="$TMPDIR_ROOT/linked repo"
git init -q "$main"
git -C "$main" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m initial
git -C "$main" worktree add -q --detach "$linked"
store="$main/.agent/checkpoints"

# list: a workspace with no checkpoints prints nothing.
assert_eq '' "$("$CHECKPOINT" list --workspace "$main")" 'list prints nothing without checkpoints'

# new: creates an empty checkpoint named after the second in canonical storage.
first=$(CHECKPOINT_TIMESTAMP=2026-01-02-030405 "$CHECKPOINT" new --workspace "$linked")
assert_eq "$store/2026-01-02-030405.md" "$first" 'new names the checkpoint after the second in canonical storage'
[[ -f $first && ! -s $first ]] || fail 'new creates an empty checkpoint'
pass 'new creates an empty checkpoint'
git -C "$main" check-ignore -q .agent/checkpoints/2026-01-02-030405.md || fail 'checkpoints are ignored'
pass 'checkpoints are ignored'

# new: a taken second is retried with a fresh timestamp and never overwritten.
printf '# Goal\n\nkeep me\n' >"$first"
CHECKPOINT_TIMESTAMP=2026-01-02-030405 assert_fails 1 'a fixed taken timestamp exhausts the attempts' \
	new --workspace "$main"
assert_eq "$(printf '# Goal\n\nkeep me')" "$(cat "$first")" 'new never overwrites a taken checkpoint'
taken=$(date '+%Y-%m-%d-%H%M%S')
printf 'taken\n' >"$store/$taken.md"
retried=$("$CHECKPOINT" new --workspace "$main")
[[ $retried != "$store/$taken.md" ]] || fail 'new retries a taken second'
assert_eq taken "$(cat "$store/$taken.md")" 'new retries a taken second without touching it'

# list: one line per checkpoint, newest first, with its goal heading.
printf 'intro\n# Second goal\n# Later heading\n' >"$store/2026-01-03-000000.md"
printf 'no heading\n' >"$store/2026-01-01-000000.md"
mkdir "$store/2026-01-04-000000" "$store/2026-01-05-000000.md"
printf '# Not a checkpoint\n' >"$store/notes.md"
listing=$("$CHECKPOINT" list --workspace "$linked")
assert_eq "$retried" "$(head -n 1 <<<"$listing" | cut -f1)" 'list starts with the newest checkpoint'
grep -qxF "$store/2026-01-03-000000.md	Second goal" <<<"$listing" || fail 'list shows the first goal heading'
pass 'list shows the first goal heading'
grep -qxF "$first	Goal" <<<"$listing" || fail 'list shows each checkpoint'
pass 'list shows each checkpoint'
assert_eq "$store/2026-01-01-000000.md	(no goal)" "$(tail -n 1 <<<"$listing")" 'list marks a checkpoint without a goal and ends with the oldest'
assert_eq 5 "$(wc -l <<<"$listing")" 'list skips folders and files not named like checkpoints'

# The target repository comes only from --workspace, never the caller's cwd.
repo_b="$TMPDIR_ROOT/repo b"
git init -q "$repo_b"
git -C "$repo_b" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m initial
isolated=$(cd "$main" && CHECKPOINT_TIMESTAMP=2026-01-02-030405 "$CHECKPOINT" new --workspace "$repo_b")
assert_eq "$repo_b/.agent/checkpoints/2026-01-02-030405.md" "$isolated" 'new stores under the --workspace repository, not the caller cwd'

# Usage errors exit 2 with no stdout.
assert_fails 2 'rejects a missing command'
assert_fails 2 'rejects an unknown command' bogus
assert_fails 2 'new rejects a missing --workspace' new
assert_fails 2 'new rejects extra arguments' new --workspace "$main" extra
assert_fails 2 'list rejects a missing --workspace' list
assert_fails 2 'list rejects extra arguments' list --workspace "$main" extra

# Other failures exit 1 with no stdout.
CHECKPOINT_TIMESTAMP=../escape assert_fails 1 'new rejects an invalid timestamp' new --workspace "$main"

# A store agent-store cannot resolve fails with agent-store's own status.
assert_fails 1 'new propagates a nonexistent workspace' new --workspace "$TMPDIR_ROOT/does not exist"
assert_fails 2 'new propagates a workspace outside any repository' new --workspace "$OUTSIDE"
