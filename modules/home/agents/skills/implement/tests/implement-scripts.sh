#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RESOLVER="$SCRIPT_DIR/../scripts/resolve-store.sh"
PREPARE_RUN="$SCRIPT_DIR/../scripts/prepare-run.sh"

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

assert_contains() {
	local needle=$1
	local haystack=$2
	local description=$3

	[[ $haystack == *"$needle"* ]] || fail "$description: expected '$needle' in '$haystack'"
	printf 'ok - %s\n' "$description"
}

assert_lacks() {
	local needle=$1
	local haystack=$2
	local description=$3

	[[ $haystack != *"$needle"* ]] || fail "$description: unexpected '$needle' in '$haystack'"
	printf 'ok - %s\n' "$description"
}

# The fixtures exercise real repositories, so a missing tool fails the suite
# rather than silently skipping the criteria that depend on it.
for tool in git jj timeout; do
	command -v "$tool" >/dev/null 2>&1 || fail "$tool is required on PATH"
done

TMPDIR_ROOT=$(mktemp -d)
TMPDIR_ROOT=$(cd "$TMPDIR_ROOT" && pwd -P)
trap 'chmod -R u+w "$TMPDIR_ROOT" 2>/dev/null; rm -rf "$TMPDIR_ROOT"' EXIT

# Isolate jj from the user's configuration. Git identity is passed per command.
export JJ_CONFIG="$TMPDIR_ROOT/jj-config.toml"
cat >"$JJ_CONFIG" <<'EOF'
user.name = "Test"
user.email = "test@example.com"
EOF

# Every helper is invoked by its absolute path with an explicit --workspace, so
# run the suite from a directory unrelated to any fixture to prove the helpers
# never derive their target from the caller's working directory.
OUTSIDE="$TMPDIR_ROOT/outside cwd"
mkdir -p "$OUTSIDE"
cd "$OUTSIDE"

git_test() {
	git -c user.name=Test -c user.email=test@example.com "$@"
}

# Runs the preparer and records its stdout, stderr, and exit status in
# prepare_out, prepare_err, and prepare_status.
run_prepare() {
	local err_file="$TMPDIR_ROOT/prepare.err"

	set +e
	prepare_out=$("$PREPARE_RUN" "$@" 2>"$err_file")
	prepare_status=$?
	set -e
	prepare_err=$(<"$err_file")
}

# Fixture N: a non-colocated jj repository at <dir>/default with a second
# workspace at <dir>/second, neither of which is a Git work tree.
make_jj_non_colocated() {
	local dir=$1

	mkdir -p "$dir"
	jj git init --no-colocate "$dir/default" >/dev/null 2>&1
	jj -R "$dir/default" workspace add --no-colocate --name second "$dir/second" >/dev/null 2>&1
	if git -C "$dir/second" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		fail 'non-colocated jj fixture must not be a Git work tree'
	fi
}

# Fixture C: a colocated jj repository at <dir>/default with a second colocated
# workspace at <dir>/second, which is a Git linked worktree.
make_jj_colocated() {
	local dir=$1

	mkdir -p "$dir"
	jj git init --colocate "$dir/default" >/dev/null 2>&1
	jj -R "$dir/default" workspace add --colocate --name second "$dir/second" >/dev/null 2>&1
	assert_eq true "$(git -C "$dir/second" rev-parse --is-inside-work-tree)" 'colocated jj second workspace is a Git work tree'
}

# Fixture G: a plain Git repository at <dir>/main with a linked worktree at
# <dir>/linked.
make_git() {
	local dir=$1

	mkdir -p "$dir"
	git init -q "$dir/main"
	git_test -C "$dir/main" commit -q --allow-empty -m initial
	git -C "$dir/main" worktree add -q --detach "$dir/linked"
}

# Asserts that neither jj workspace reports any .agent/ path as a change.
assert_jj_untracked() {
	local name=$1
	local ws

	for ws in "$2" "$3"; do
		assert_lacks .agent/ "$(jj -R "$ws" status)" "$name: jj status in $(basename "$ws") lists no .agent/ path"
		assert_lacks .agent/ "$(jj -R "$ws" diff --summary)" "$name: jj diff in $(basename "$ws") lists no .agent/ path"
	done
}

count_operations() {
	jj --ignore-working-copy -R "$1" op log --no-graph -T 'id ++ "\n"' | wc -l
}

# Reserving from a non-default workspace must not snapshot the default
# workspace, whose working copy that workspace owns. This runs first on a fresh
# fixture so no earlier jj command has snapshotted the untracked file.
fresh="$TMPDIR_ROOT/fresh jj"
make_jj_non_colocated "$fresh"
printf '%s\n' untracked >"$fresh/default/untracked.txt"
operations_before=$(count_operations "$fresh/default")
run_prepare --workspace "$fresh/second" snapshot
assert_status 0 "$prepare_status" 'reservation from a jj workspace succeeds'
assert_eq "$operations_before" "$(count_operations "$fresh/default")" 'reservation does not snapshot another workspace'

# Fixture N resolves to the default workspace and keeps run files untracked.
non_colocated="$TMPDIR_ROOT/non colocated"
make_jj_non_colocated "$non_colocated"
run_prepare --workspace "$non_colocated/second" 'Fast Run!'
assert_status 0 "$prepare_status" 'non-colocated jj reservation succeeds'
assert_eq "$non_colocated/default/.agent/implement" "$(dirname "$prepare_out")" 'non-colocated jj run directory is under the default workspace'
[[ -d $prepare_out ]] || fail 'non-colocated jj run directory exists'
assert_eq '' "$(ls -A "$prepare_out")" 'run directory is created empty'
assert_eq '*' "$(<"$non_colocated/default/.agent/implement/.gitignore")" 'run store ignores all contents'
printf '%s\n' run >"$prepare_out/briefs.md"
assert_jj_untracked 'non-colocated jj' "$non_colocated/default" "$non_colocated/second"

# Fixture C resolves through Git to the main worktree.
colocated="$TMPDIR_ROOT/colocated"
make_jj_colocated "$colocated"
run_prepare --workspace "$colocated/second" colocated
assert_status 0 "$prepare_status" 'colocated jj reservation succeeds'
assert_eq "$colocated/default/.agent/implement" "$(dirname "$prepare_out")" 'colocated jj run directory is under the main worktree'
printf '%s\n' run >"$prepare_out/briefs.md"
assert_jj_untracked 'colocated jj' "$colocated/default" "$colocated/second"

# Fixture G resolves to the main worktree, normalizes slugs, and avoids
# collisions between reservations with the same name.
plain="$TMPDIR_ROOT/plain git"
make_git "$plain"
IMPLEMENT_TIMESTAMP=2026-01-02-030405 run_prepare --workspace "$plain/linked" 'Fast Run!'
assert_status 0 "$prepare_status" 'Git reservation succeeds'
assert_eq "$plain/main/.agent/implement/2026-01-02-030405-fast-run" "$prepare_out" 'Git run directory is under the main worktree with a normalized slug'
first_run=$prepare_out
printf '%s\n' run >"$first_run/briefs.md"
assert_eq '' "$(git -C "$plain/main" status --porcelain)" 'Git main worktree status lists no run files'
assert_eq '' "$(git -C "$plain/linked" status --porcelain)" 'Git linked worktree status lists no run files'

IMPLEMENT_TIMESTAMP=2026-01-02-030405 run_prepare --workspace "$plain/linked" 'Fast Run!'
assert_eq "$first_run-2" "$prepare_out" 'second reservation with the same name gets a -2 suffix'
IMPLEMENT_TIMESTAMP=2026-01-02-030405 run_prepare --workspace "$plain/linked" 'Fast Run!'
assert_eq "$first_run-3" "$prepare_out" 'third reservation with the same name gets a -3 suffix'

IMPLEMENT_TIMESTAMP=2026-01-02-030405 run_prepare --workspace "$plain/main"
assert_eq "$plain/main/.agent/implement/2026-01-02-030405-run" "$prepare_out" 'missing slug defaults to run'
IMPLEMENT_TIMESTAMP=2026-01-02-030405 run_prepare --workspace "$plain/main" '!!!'
assert_eq "$plain/main/.agent/implement/2026-01-02-030405-run-2" "$prepare_out" 'slug without alphanumerics defaults to run'

IMPLEMENT_TIMESTAMP=../escape run_prepare --workspace "$plain/main" rejected
assert_status 1 "$prepare_status" 'invalid run timestamp is rejected'
assert_contains 'invalid run timestamp' "$prepare_err" 'invalid run timestamp reports the reason'

# A failure other than an existing name stops with the error instead of
# retrying further suffixes.
store="$plain/main/.agent/implement"
entries_before=$(ls -A "$store")
chmod a-w "$store"
set +e
unwritable_err=$(IMPLEMENT_TIMESTAMP=2026-01-02-030405 timeout 10 "$PREPARE_RUN" --workspace "$plain/main" unwritable 2>&1 >/dev/null)
unwritable_status=$?
set -e
chmod u+w "$store"
[[ $unwritable_status -ne 0 && $unwritable_status -ne 124 ]] ||
	fail "unwritable store fails without retrying: got status $unwritable_status"
printf '%s\n' 'ok - unwritable store fails without retrying'
assert_contains 'could not reserve' "$unwritable_err" 'unwritable store reports the error'
assert_eq "$entries_before" "$(ls -A "$store")" 'unwritable store gains no run directory'

# The caller's working directory, here a different repository, never selects
# the store.
cross_out=$(cd "$plain/main" && "$PREPARE_RUN" --workspace "$non_colocated/second" cross)
assert_eq "$non_colocated/default/.agent/implement" "$(dirname "$cross_out")" 'preparer stores under the --workspace repository, not the caller cwd'
assert_eq "$plain/main" "$(cd "$non_colocated/default" && "$RESOLVER" --workspace "$plain/linked")" 'resolver targets the --workspace repository, not the caller cwd'

# Fixture A: no workspace is named default, so storage is ambiguous.
ambiguous="$TMPDIR_ROOT/ambiguous"
make_jj_non_colocated "$ambiguous"
jj -R "$ambiguous/default" workspace rename renamed >/dev/null 2>&1
run_prepare --workspace "$ambiguous/second" ambiguous
assert_status 3 "$prepare_status" 'ambiguous storage is rejected'
assert_eq '' "$prepare_out" 'ambiguous storage prints no path'
[[ ! -e $ambiguous/default/.agent/implement && ! -e $ambiguous/second/.agent/implement ]] ||
	fail 'ambiguous storage creates no run store'
printf '%s\n' 'ok - ambiguous storage creates no run store'

# A store tracked by Git is refused.
git_tracked="$TMPDIR_ROOT/git tracked"
make_git "$git_tracked"
mkdir -p "$git_tracked/main/.agent/implement"
printf '%s\n' tracked >"$git_tracked/main/.agent/implement/existing.md"
git -C "$git_tracked/main" add .agent/implement/existing.md
git_test -C "$git_tracked/main" commit -qm tracked
run_prepare --workspace "$git_tracked/linked" rejected
assert_status 1 "$prepare_status" 'Git-tracked run store is rejected'
assert_contains 'must be entirely untracked' "$prepare_err" 'Git-tracked run store reports the reason'

# A store committed in jj is refused, even when checked from another workspace
# and from an unrelated cwd, which requires a root-relative fileset.
jj_tracked="$TMPDIR_ROOT/jj tracked"
make_jj_non_colocated "$jj_tracked"
mkdir -p "$jj_tracked/default/.agent/implement"
printf '%s\n' tracked >"$jj_tracked/default/.agent/implement/existing.md"
jj -R "$jj_tracked/default" commit -m tracked >/dev/null 2>&1
run_prepare --workspace "$jj_tracked/second" rejected
assert_status 1 "$prepare_status" 'jj-tracked run store is rejected'
assert_contains 'must be entirely untracked' "$prepare_err" 'jj-tracked run store reports the reason'

# A store .gitignore that does not ignore everything is refused.
partial_ignore="$TMPDIR_ROOT/partial ignore"
make_git "$partial_ignore"
mkdir -p "$partial_ignore/main/.agent/implement"
printf '%s\n' '*' '*.tmp' >"$partial_ignore/main/.agent/implement/.gitignore"
run_prepare --workspace "$partial_ignore/main" rejected
assert_status 1 "$prepare_status" 'partial run store ignore file is rejected'
assert_contains "must ignore everything with '*'" "$prepare_err" 'partial run store ignore file reports the reason'
assert_eq '.gitignore' "$(ls -A "$partial_ignore/main/.agent/implement")" 'partial run store ignore file gains no run directory'

# CLI validation: usage errors exit 2 with empty stdout before any discovery.
run_prepare
assert_status 2 "$prepare_status" 'preparer rejects a missing --workspace'
assert_eq '' "$prepare_out" 'preparer missing --workspace prints no stdout'
run_prepare --workspace
assert_status 2 "$prepare_status" 'preparer rejects --workspace without a value'
run_prepare --bogus "$plain/main"
assert_status 2 "$prepare_status" 'preparer rejects an unknown option'
run_prepare --workspace "$plain/main" slug extra
assert_status 2 "$prepare_status" 'preparer rejects extra arguments'
run_prepare --workspace relative/path slug
assert_status 2 "$prepare_status" 'preparer rejects a relative workspace'
run_prepare --workspace "$TMPDIR_ROOT/does not exist" slug
assert_status 1 "$prepare_status" 'preparer propagates a nonexistent workspace failure'
assert_eq '' "$prepare_out" 'preparer nonexistent workspace prints no stdout'
