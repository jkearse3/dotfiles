#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
PREPARE_PATH="$SKILL_DIR/scripts/prepare-path.sh"
RESOLVE_SCRATCHPAD="$SKILL_DIR/scripts/resolve-scratchpad.sh"
RESOLVE_WORKSPACE="$SKILL_DIR/scripts/resolve-workspace.sh"
TMPDIR_ROOT=$(mktemp -d)
TMPDIR_ROOT=$(cd "$TMPDIR_ROOT" && pwd -P)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

assert_eq() {
	local expected=$1
	local actual=$2
	local message=$3
	[[ $actual == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
	printf 'ok - %s\n' "$message"
}

assert_failure() {
	local expected_message=$1
	shift
	local status=0
	"$@" >"$TMPDIR_ROOT/failure.stdout" 2>"$TMPDIR_ROOT/failure.stderr" || status=$?
	[[ $status -ne 0 ]] || fail "command unexpectedly succeeded: $*"
	grep -Fq "$expected_message" "$TMPDIR_ROOT/failure.stderr" ||
		fail "failure did not contain '$expected_message'"
	printf 'ok - rejected: %s\n' "$expected_message"
}

main="$TMPDIR_ROOT/main"
linked="$TMPDIR_ROOT/linked"
unrelated="$TMPDIR_ROOT/unrelated"
mkdir -p "$main" "$unrelated"
git -C "$main" init -q
git -C "$main" config user.name Test
git -C "$main" config user.email test@example.com
printf 'tracked\n' >"$main/tracked"
git -C "$main" add tracked
git -C "$main" commit -qm initial
git -C "$main" worktree add -qb linked-worktree "$linked"

assert_eq "$main" "$("$RESOLVE_WORKSPACE" --workspace "$main")" 'main worktree resolves to itself'
assert_eq "$linked" "$("$RESOLVE_WORKSPACE" --workspace "$linked")" 'linked worktree resolves to itself'

main_path=$(cd "$unrelated" && SCRATCHPAD_TIMESTAMP=2026-01-02-030405 \
	"$PREPARE_PATH" --workspace "$main" 'Refactor Auth Flow!')
linked_path=$(cd "$unrelated" && SCRATCHPAD_TIMESTAMP=2026-01-02-030405 \
	"$PREPARE_PATH" --workspace "$linked" 'Refactor Auth Flow!')
assert_eq "$main/.agent/scratchpads/2026-01-02-030405-refactor-auth-flow.md" "$main_path" \
	'main scratchpad uses the main worktree'
assert_eq "$linked/.agent/scratchpads/2026-01-02-030405-refactor-auth-flow.md" "$linked_path" \
	'linked scratchpad stays in the linked worktree'
[[ -f $main_path && -f $linked_path ]] || fail 'prepared scratchpads are regular files'
assert_eq '*' "$(<"$main/.agent/scratchpads/.gitignore")" 'store self-ignores all contents'
git -C "$main" check-ignore -q .agent/scratchpads/example.md || fail 'main scratchpads are ignored'
git -C "$linked" check-ignore -q .agent/scratchpads/example.md || fail 'linked scratchpads are ignored'
printf 'ok - each worktree ignores its local scratchpads\n'

printf 'main state\n' >"$main_path"
printf 'linked state\n' >"$linked_path"
assert_eq "$main_path" "$("$RESOLVE_SCRATCHPAD" --workspace "$main" "$(basename "$main_path")")" \
	'exact filename resolves in its worktree'
assert_eq "$linked_path" "$("$RESOLVE_SCRATCHPAD" --workspace "$linked" "$linked_path")" \
	'exact absolute path resolves in its worktree'
assert_eq "$main_path" "$("$RESOLVE_SCRATCHPAD" --workspace "$main")" \
	'listing contains only the current worktree scratchpad'

collision_path=$(SCRATCHPAD_TIMESTAMP=2026-01-02-030405 \
	"$PREPARE_PATH" --workspace "$linked" 'Refactor Auth Flow!')
assert_eq "$linked/.agent/scratchpads/2026-01-02-030405-refactor-auth-flow--2.md" "$collision_path" \
	'same-second collisions receive a numeric suffix'

printf -v overlong_slug '%*s' 1024 ''
overlong_slug=${overlong_slug// /x}
reservation_status=0
SCRATCHPAD_TIMESTAMP=2026-01-02-050607 \
	"$PREPARE_PATH" --workspace "$linked" "$overlong_slug" \
	>"$TMPDIR_ROOT/reservation.stdout" 2>"$TMPDIR_ROOT/reservation.stderr" || reservation_status=$?
[[ $reservation_status -ne 0 ]] || fail 'non-collision reservation failure must be rejected'
grep -Fq 'prepare-path: could not reserve' "$TMPDIR_ROOT/reservation.stderr" ||
	fail 'non-collision reservation failure must be diagnosed'
printf 'ok - permanent reservation errors fail instead of consuming suffixes\n'

assert_failure 'not a regular scratchpad' \
	"$RESOLVE_SCRATCHPAD" --workspace "$main" "$linked_path"
assert_failure 'invalid scratchpad timestamp' \
	env SCRATCHPAD_TIMESTAMP=not-a-time "$PREPARE_PATH" --workspace "$main" invalid-time

nonrepo="$TMPDIR_ROOT/plain workspace"
mkdir -p "$nonrepo"
plain_path=$(SCRATCHPAD_TIMESTAMP=2026-01-02-040506 \
	"$PREPARE_PATH" --workspace "$nonrepo" 'Plain Workspace')
assert_eq "$nonrepo/.agent/scratchpads/2026-01-02-040506-plain-workspace.md" "$plain_path" \
	'non-versioned workspace uses its explicit root'

malformed="$TMPDIR_ROOT/malformed"
mkdir -p "$malformed/.agent/scratchpads"
git -C "$malformed" init -q
git -C "$malformed" config user.name Test
git -C "$malformed" config user.email test@example.com
git -C "$malformed" commit -q --allow-empty -m initial
printf '*.md\n' >"$malformed/.agent/scratchpads/.gitignore"
assert_failure 'must be a regular file containing exactly *' \
	"$PREPARE_PATH" --workspace "$malformed" malformed-ignore

tracked="$TMPDIR_ROOT/tracked-store"
mkdir -p "$tracked/.agent/scratchpads"
git -C "$tracked" init -q
git -C "$tracked" config user.name Test
git -C "$tracked" config user.email test@example.com
printf 'tracked state\n' >"$tracked/.agent/scratchpads/existing.md"
git -C "$tracked" add .agent/scratchpads/existing.md
git -C "$tracked" commit -qm tracked
assert_failure '.agent/scratchpads must be entirely untracked' \
	"$PREPARE_PATH" --workspace "$tracked" tracked-store

skill_content=$(<"$SKILL_DIR/SKILL.md")
[[ $skill_content == *'fresh agent given only the scratchpad and its'* ]] ||
	fail 'skill must preserve the fresh-agent recovery test'
[[ $skill_content == *'Do not write after every routine action.'* ]] ||
	fail 'skill must keep updates event-driven'
[[ $skill_content == *"repository's primary checkout"* ]] ||
	fail 'skill must require worktree-local storage'
printf 'ok - skill preserves recovery, update, and worktree-local invariants\n'
