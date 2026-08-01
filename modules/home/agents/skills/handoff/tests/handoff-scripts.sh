#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RESOLVER="$SCRIPT_DIR/../scripts/resolve-store.sh"
PREPARE_PATH="$SCRIPT_DIR/../scripts/prepare-path.sh"
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

plain_result=$(cd "$main" && "$RESOLVER")
assert_eq "$main" "$plain_result" 'plain Git uses its main worktree'

git -C "$main" worktree add -q --detach "$linked"
primary_result=$(cd "$main" && "$RESOLVER")
linked_result=$(cd "$linked" && "$RESOLVER")
assert_eq "$main" "$primary_result" 'primary checkout resolves canonical storage'
assert_eq "$main" "$linked_result" 'linked checkout resolves primary storage with spaces'

prepared_path=$(cd "$linked" && HANDOFF_TIMESTAMP=2026-01-02-030405 "$PREPARE_PATH" 'Fast Handoff!')
assert_eq "$main/.agent/handoffs" "$(dirname "$prepared_path")" 'handoff path uses canonical storage'
[[ $(basename "$prepared_path") == *-fast-handoff.md ]] || fail 'handoff path normalizes its slug'
[[ -f $prepared_path ]] || fail 'handoff path is reserved atomically'
printf '%s\n' 'ok - handoff path is reserved atomically'
assert_eq '*' "$(<"$main/.agent/handoffs/.gitignore")" 'handoff store ignores all contents'
git -C "$main" check-ignore -q .agent/handoffs/example.md || fail 'handoff artifacts are ignored'

collision_path=$(cd "$linked" && HANDOFF_TIMESTAMP=2026-01-02-030405 "$PREPARE_PATH" 'Fast Handoff!')
[[ $collision_path == *-fast-handoff-2.md ]] || fail 'handoff path avoids collisions'
printf '%s\n' 'ok - handoff path avoids collisions'

set +e
(cd "$linked" && HANDOFF_TIMESTAMP=../escape "$PREPARE_PATH" rejected >/dev/null 2>&1)
timestamp_status=$?
set -e
assert_status 1 "$timestamp_status" 'invalid handoff timestamp is rejected'

tracked="$TMPDIR_ROOT/tracked store"
git init -q "$tracked"
mkdir -p "$tracked/.agent/handoffs"
printf '%s\n' tracked >"$tracked/.agent/handoffs/existing.md"
git -C "$tracked" add .agent/handoffs/existing.md
git -C "$tracked" -c user.name=Test -c user.email=test@example.com commit -qm tracked
set +e
(cd "$tracked" && "$PREPARE_PATH" rejected >/dev/null 2>&1)
tracked_status=$?
set -e
assert_status 1 "$tracked_status" 'tracked handoff store is rejected'

malformed="$TMPDIR_ROOT/malformed ignore"
git init -q "$malformed"
git -C "$malformed" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m initial
mkdir -p "$malformed/.agent/handoffs"
printf '%s\n' '*.tmp' >"$malformed/.agent/handoffs/.gitignore"
set +e
(cd "$malformed" && "$PREPARE_PATH" rejected >/dev/null 2>&1)
malformed_status=$?
set -e
assert_status 1 "$malformed_status" 'malformed handoff ignore file is rejected'

(
	# Invoked indirectly by the preparer child process.
	# shellcheck disable=SC2329
	git() {
		case "$*" in
		*rev-parse*)
			printf '%s\n' true
			;;
		*ls-files*)
			return 1
			;;
		*)
			command git "$@"
			;;
		esac
	}
	export -f git
	set +e
	(cd "$main" && "$PREPARE_PATH" rejected >/dev/null 2>&1)
	git_inspection_status=$?
	set -e
	assert_status 1 "$git_inspection_status" 'Git tracking inspection failure is rejected'
)

(
	# Invoked indirectly by the preparer child process.
	# shellcheck disable=SC2329
	git() {
		return 1
	}
	# shellcheck disable=SC2329
	jj() {
		case "$*" in
		'--ignore-working-copy workspace root')
			printf '%s\n' "$TMPDIR_ROOT/pure jj"
			;;
		'--ignore-working-copy workspace root --name default')
			printf '%s\n' "$TMPDIR_ROOT/pure jj"
			;;
		-R*status)
			: >"$TMPDIR_ROOT/jj-snapshot-ran"
			;;
		--ignore-working-copy*-R*file\ list*)
			[[ -f $TMPDIR_ROOT/jj-snapshot-ran ]] || fail 'pure jj check must snapshot first'
			printf '%s\n' '.agent/handoffs/tracked.md'
			;;
		*)
			return 1
			;;
		esac
	}
	export TMPDIR_ROOT
	export -f git jj
	mkdir -p "$TMPDIR_ROOT/pure jj"
	set +e
	(cd "$TMPDIR_ROOT/pure jj" && "$PREPARE_PATH" rejected >/dev/null 2>&1)
	pure_jj_status=$?
	set -e
	assert_status 1 "$pure_jj_status" 'pure jj tracked handoff store is rejected after snapshot'
)

(
	# Invoked indirectly by the preparer child process.
	# shellcheck disable=SC2329
	git() {
		return 1
	}
	# shellcheck disable=SC2329
	jj() {
		case "$*" in
		'--ignore-working-copy workspace root' | '--ignore-working-copy workspace root --name default')
			printf '%s\n' "$TMPDIR_ROOT/pure jj failure"
			;;
		-R*status)
			return 0
			;;
		--ignore-working-copy*-R*file\ list*)
			return 1
			;;
		*)
			return 1
			;;
		esac
	}
	export TMPDIR_ROOT
	export -f git jj
	mkdir -p "$TMPDIR_ROOT/pure jj failure"
	set +e
	(cd "$TMPDIR_ROOT/pure jj failure" && "$PREPARE_PATH" rejected >/dev/null 2>&1)
	jj_inspection_status=$?
	set -e
	assert_status 1 "$jj_inspection_status" 'jj tracking inspection failure is rejected'
)

bare="$TMPDIR_ROOT/bare repo.git"
git init -q --bare "$bare"
set +e
(cd "$bare" && "$RESOLVER" >/dev/null 2>&1)
bare_status=$?
set -e
assert_status 2 "$bare_status" 'bare Git repositories are not worktrees'

(
	# Invoked indirectly by the resolver child process.
	# shellcheck disable=SC2329
	git() {
		command git "$@"
	}
	# shellcheck disable=SC2329
	jj() {
		fail 'jj should not run for a colocated Git repository'
	}
	export -f git jj fail
	result=$(cd "$linked" && "$RESOLVER")
	assert_eq "$main" "$result" 'colocated repositories prefer Git main worktree'
)

if command -v jj-ensure >/dev/null 2>&1 && command -v jj >/dev/null 2>&1; then
	jj_main="$TMPDIR_ROOT/jj main"
	jj_linked="$TMPDIR_ROOT/jj linked"
	git init -q "$jj_main"
	git -C "$jj_main" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m initial
	(cd "$jj_main" && jj-ensure >/dev/null)
	jj -R "$jj_main" workspace add --name secondary "$jj_linked" >/dev/null 2>&1
	if (cd "$jj_linked" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
		fail 'jj linked fixture must not be a Git worktree'
	fi
	assert_eq "$jj_main" "$(cd "$jj_linked" && "$RESOLVER")" 'non-Git jj workspace resolves its default workspace'
fi

run_mock_jj() (
	local mode=$1
	local expected_status=$2
	local expected_output=$3

	# Invoked indirectly by the resolver child process.
	# shellcheck disable=SC2329
	git() {
		return 1
	}
	# shellcheck disable=SC2329
	jj() {
		if [[ $1 != --ignore-working-copy || $2 != workspace ]]; then
			return 1
		fi

		case "$MODE:$3:${4:-}" in
		default:root:)
			printf '%s\n' '/work/current'
			;;
		default:root:--name)
			printf '%s\n' '/work/default'
			;;
		sole:root:)
			printf '%s\n' '/work/sole'
			;;
		sole:root:--name)
			return 1
			;;
		sole:list:-T)
			printf 'solo\n'
			;;
		ambiguous:root:)
			printf '%s\n' '/work/current'
			;;
		ambiguous:root:--name)
			return 1
			;;
		ambiguous:list:-T)
			printf 'one\ntwo\n'
			;;
		outside:root:)
			return 1
			;;
		*)
			return 1
			;;
		esac
	}
	export MODE=$mode
	export -f git jj

	set +e
	output=$($RESOLVER 2>/dev/null)
	status=$?
	set -e
	assert_status "$expected_status" "$status" "mock jj $mode status"
	assert_eq "$expected_output" "$output" "mock jj $mode result"
)

run_mock_jj default 0 /work/default
run_mock_jj sole 0 /work/sole
run_mock_jj ambiguous 3 ''
run_mock_jj outside 2 ''
