#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RESOLVER="$SCRIPT_DIR/../scripts/resolve-store.sh"
PREPARE_PATH="$SCRIPT_DIR/../scripts/prepare-path.sh"
RESOLVE_PLAN="$SCRIPT_DIR/../scripts/resolve-plan.sh"
TMPDIR_ROOT=$(mktemp -d)
TMPDIR_ROOT=$(cd "$TMPDIR_ROOT" && pwd -P)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Every helper runs from a directory unrelated to any fixture so the scripts are
# exercised for working-directory independence: the target is chosen only by the
# explicit --workspace argument, never by the caller's cwd. The path contains a
# space so quoting regressions surface.
UNRELATED_CWD="$TMPDIR_ROOT/unrelated cwd"
mkdir -p "$UNRELATED_CWD"

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

assert_empty_regular_file() {
	local path=$1
	local description=$2

	[[ -f $path && ! -L $path ]] || fail "$description: expected an existing regular non-symlink file"
	[[ ! -s $path ]] || fail "$description: expected an empty file"
	printf 'ok - %s\n' "$description"
}

# Run an arbitrary helper invocation from the unrelated cwd and assert a failure
# status, an empty stdout, and an exact diagnostic. Used for CLI and forwarded
# operational failures where no --workspace is auto-injected.
assert_run_failure() {
	local expected_status=$1
	local expected_diagnostic=$2
	local description=$3
	local stdout_file="$TMPDIR_ROOT/run-stdout"
	local stderr_file="$TMPDIR_ROOT/run-stderr"
	local status
	shift 3

	set +e
	(cd "$UNRELATED_CWD" && "$@") >"$stdout_file" 2>"$stderr_file"
	status=$?
	set -e

	assert_status "$expected_status" "$status" "$description has expected status"
	[[ ! -s $stdout_file ]] || fail "$description: expected no stdout"
	printf 'ok - %s\n' "$description has no stdout"
	assert_eq "$expected_diagnostic" "$(<"$stderr_file")" "$description has expected diagnostic"
}

# Run resolve-plan against an explicit workspace from the unrelated cwd and
# assert a failure status, empty stdout, and an exact diagnostic.
assert_plan_failure() {
	local workspace=$1
	local expected_status=$2
	local expected_diagnostic=$3
	local description=$4
	local stdout_file="$TMPDIR_ROOT/plan-stdout"
	local stderr_file="$TMPDIR_ROOT/plan-stderr"
	local status
	shift 4

	set +e
	(cd "$UNRELATED_CWD" && "$RESOLVE_PLAN" --workspace "$workspace" "$@") >"$stdout_file" 2>"$stderr_file"
	status=$?
	set -e

	assert_status "$expected_status" "$status" "$description has expected status"
	[[ ! -s $stdout_file ]] || fail "$description: expected no stdout"
	printf 'ok - %s\n' "$description has no stdout"
	assert_eq "$expected_diagnostic" "$(<"$stderr_file")" "$description has expected diagnostic"
}

assert_resolver_ambiguity() {
	local workspace=$1
	local expected_diagnostic=$2
	local description=$3
	local stdout_file="$TMPDIR_ROOT/resolver-stdout"
	local stderr_file="$TMPDIR_ROOT/resolver-stderr"
	local status

	set +e
	(cd "$UNRELATED_CWD" && "$RESOLVER" --workspace "$workspace") >"$stdout_file" 2>"$stderr_file"
	status=$?
	set -e

	assert_status 3 "$status" "$description has ambiguity status"
	[[ ! -s $stdout_file ]] || fail "$description: expected no stdout"
	printf 'ok - %s\n' "$description has no stdout"
	assert_eq "$expected_diagnostic" "$(<"$stderr_file")" "$description has the expected diagnostic"
}

store_usage='usage: resolve-store.sh --workspace <absolute-workspace>'
prepare_usage='usage: prepare-path.sh --workspace <absolute-workspace> [slug]'
usage_diagnostic='usage: resolve-plan.sh --workspace <absolute-workspace> [exact-filename-or-canonical-path]'

# Malformed and relative workspace arguments fail as usage errors, and
# nonexistent or non-directory workspaces fail as operational errors, before any
# repository discovery.
nonexistent_workspace="$TMPDIR_ROOT/nonexistent workspace"
file_workspace="$TMPDIR_ROOT/file workspace"
printf 'not a directory\n' >"$file_workspace"
not_a_directory_diagnostic="resolve-store: workspace is not a directory: $nonexistent_workspace"

assert_run_failure 2 "$store_usage" 'resolver rejects missing --workspace' "$RESOLVER"
assert_run_failure 2 "$store_usage" 'resolver rejects missing workspace value' "$RESOLVER" --workspace
assert_run_failure 2 "$store_usage" 'resolver rejects unknown option' "$RESOLVER" --bogus
assert_run_failure 2 "$store_usage" 'resolver rejects extra arguments' "$RESOLVER" --workspace "$TMPDIR_ROOT" extra
assert_run_failure 2 "$store_usage" 'resolver rejects relative workspace' "$RESOLVER" --workspace relative/workspace
assert_run_failure 1 "$not_a_directory_diagnostic" 'resolver rejects nonexistent workspace' "$RESOLVER" --workspace "$nonexistent_workspace"
assert_run_failure 1 "resolve-store: workspace is not a directory: $file_workspace" 'resolver rejects non-directory workspace' "$RESOLVER" --workspace "$file_workspace"

# The public helpers parse their own CLI before invoking the resolver, then
# forward the workspace so the resolver's operational rejections propagate.
assert_run_failure 2 "$usage_diagnostic" 'resolve-plan rejects missing --workspace' "$RESOLVE_PLAN"
assert_run_failure 2 "$usage_diagnostic" 'resolve-plan rejects missing workspace value' "$RESOLVE_PLAN" --workspace
assert_run_failure 2 "$store_usage" 'resolve-plan propagates resolver relative-workspace rejection' "$RESOLVE_PLAN" --workspace relative/workspace
assert_run_failure 1 "$not_a_directory_diagnostic" 'resolve-plan propagates resolver nonexistent-workspace rejection' "$RESOLVE_PLAN" --workspace "$nonexistent_workspace"

assert_run_failure 2 "$prepare_usage" 'prepare-path rejects missing --workspace' "$PREPARE_PATH"
assert_run_failure 2 "$prepare_usage" 'prepare-path rejects missing workspace value' "$PREPARE_PATH" --workspace
assert_run_failure 2 "$prepare_usage" 'prepare-path rejects too many arguments' "$PREPARE_PATH" --workspace "$TMPDIR_ROOT" slug extra
assert_run_failure 1 "$not_a_directory_diagnostic" 'prepare-path propagates resolver nonexistent-workspace rejection' "$PREPARE_PATH" --workspace "$nonexistent_workspace" slug

# Well-formed CLI whose trailing identifier is malformed still fails before any
# repository discovery because the workspace target is only parsed here.
assert_plan_failure "$TMPDIR_ROOT" 2 "$usage_diagnostic" 'unknown option precedes repository discovery' --latest
assert_plan_failure "$TMPDIR_ROOT" 2 "$usage_diagnostic" 'extra arguments precede repository discovery' first second

# Build disposable primary and linked worktrees. Paths contain spaces to verify
# that every script preserves path boundaries when passing values to Git.
main="$TMPDIR_ROOT/main repo"
linked="$TMPDIR_ROOT/linked repo"
git init -q "$main"
git -C "$main" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q --allow-empty -m initial
git -C "$main" worktree add -q --detach "$linked"

assert_eq "$main" "$(cd "$UNRELATED_CWD" && "$RESOLVER" --workspace "$main")" 'primary checkout resolves canonical storage'
assert_eq "$main" "$(cd "$UNRELATED_CWD" && "$RESOLVER" --workspace "$linked")" 'linked checkout resolves primary storage with spaces'

# Discovery treats absent and empty safe stores as successful empty listings.
absent_store="$TMPDIR_ROOT/absent store"
git init -q "$absent_store"
git -C "$absent_store" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q --allow-empty -m initial
assert_eq '' "$(cd "$UNRELATED_CWD" && "$RESOLVE_PLAN" --workspace "$absent_store")" 'absent plan store lists no plans'
assert_plan_failure \
	"$absent_store" \
	1 \
	"resolve-plan: plan store does not exist: $absent_store/.agent/plans" \
	'absent plan store cannot validate an exact filename' \
	'2026-01-02-030405-missing.md'

empty_store="$TMPDIR_ROOT/empty store"
git init -q "$empty_store"
git -C "$empty_store" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q --allow-empty -m initial
mkdir -p "$empty_store/.agent/plans"
printf '*\n' >"$empty_store/.agent/plans/.gitignore"
assert_eq '' "$(cd "$UNRELATED_CWD" && "$RESOLVE_PLAN" --workspace "$empty_store")" 'empty safe plan store lists no plans'

# Existing non-directory store nodes are unsafe rather than absent.
regular_store="$TMPDIR_ROOT/regular store node"
git init -q "$regular_store"
git -C "$regular_store" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q --allow-empty -m initial
mkdir "$regular_store/.agent"
printf 'not a directory\n' >"$regular_store/.agent/plans"
assert_plan_failure \
	"$regular_store" \
	1 \
	"resolve-plan: plan store path must use directories: $regular_store/.agent/plans" \
	'regular plan store node is rejected'

fifo_store="$TMPDIR_ROOT/fifo store node"
git init -q "$fifo_store"
git -C "$fifo_store" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q --allow-empty -m initial
mkdir "$fifo_store/.agent"
mkfifo "$fifo_store/.agent/plans"
assert_plan_failure \
	"$fifo_store" \
	1 \
	"resolve-plan: plan store path must use directories: $fifo_store/.agent/plans" \
	'FIFO plan store node is rejected'

regular_agent="$TMPDIR_ROOT/regular agent node"
git init -q "$regular_agent"
git -C "$regular_agent" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q --allow-empty -m initial
printf 'not a directory\n' >"$regular_agent/.agent"
assert_plan_failure \
	"$regular_agent" \
	1 \
	"resolve-plan: plan store path must use directories: $regular_agent/.agent/plans" \
	'regular agent node is rejected'

# A separate Git directory does not provide a canonical-primary backlink that a
# linked worktree can use. Reject both checkout perspectives as unsupported.
separate_checkout="$TMPDIR_ROOT/separate checkout"
separate_git_dir="$TMPDIR_ROOT/separate git dir"
separate_linked="$TMPDIR_ROOT/separate linked"
git init -q --separate-git-dir="$separate_git_dir" "$separate_checkout"
git -C "$separate_checkout" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q --allow-empty -m initial
git -C "$separate_checkout" worktree add -q --detach "$separate_linked"
unsupported_diagnostic='resolve-store: unsupported non-bare Git topology does not expose a canonical primary worktree with a .git directory; choose a canonical workspace'

assert_resolver_ambiguity "$separate_checkout" "$unsupported_diagnostic" 'separate-git-dir initial checkout'
assert_resolver_ambiguity "$separate_linked" "$unsupported_diagnostic" 'separate-git-dir linked checkout'

# A bare repository with multiple linked worktrees remains a distinct ambiguity.
bare_repo="$TMPDIR_ROOT/bare repo"
bare_linked_one="$TMPDIR_ROOT/bare linked one"
bare_linked_two="$TMPDIR_ROOT/bare linked two"
git init -q --bare "$bare_repo"
git -C "$main" push -q "$bare_repo" HEAD:refs/heads/main
git --git-dir="$bare_repo" worktree add -q --detach "$bare_linked_one" refs/heads/main
git --git-dir="$bare_repo" worktree add -q --detach "$bare_linked_two" refs/heads/main
bare_diagnostic='resolve-store: bare-backed Git repository has multiple worktrees; choose a canonical workspace'

assert_resolver_ambiguity "$bare_linked_one" "$bare_diagnostic" 'bare-backed first linked checkout'
assert_resolver_ambiguity "$bare_linked_two" "$bare_diagnostic" 'bare-backed second linked checkout'

# First use initializes the ignored store and reserves a canonical plan file.
prepared_path=$(cd "$UNRELATED_CWD" && PLAN_TIMESTAMP=2026-01-02-030405 "$PREPARE_PATH" --workspace "$linked" 'Detailed Plan!')
assert_eq "$main/.agent/plans/2026-01-02-030405-detailed-plan.md" "$prepared_path" 'plan path uses canonical timestamped storage'
assert_empty_regular_file "$prepared_path" 'prepared plan path is reserved empty'
assert_eq '*' "$(<"$main/.agent/plans/.gitignore")" 'plan store ignores all contents'
git -C "$main" check-ignore -q .agent/plans/example.md || fail 'plan artifacts are ignored'
printf '%s\n' 'ok - plan artifacts are ignored'

# Simulate the skill writing a complete plan directly to its prepared path.
source_plan="$TMPDIR_ROOT/source-plan.md"
printf '%s\n' original >"$source_plan"
cp "$source_plan" "$prepared_path"
assert_eq original "$(<"$prepared_path")" 'published plan is complete'

# Exact filenames and canonical paths validate across worktrees.
assert_eq "$prepared_path" "$(cd "$UNRELATED_CWD" && "$RESOLVE_PLAN" --workspace "$linked" "$(basename "$prepared_path")")" 'exact filename resolves'
assert_eq "$prepared_path" "$(cd "$UNRELATED_CWD" && "$RESOLVE_PLAN" --workspace "$linked" "$prepared_path")" 'canonical absolute path resolves'

# A same-second name collision gets --2 and remains a distinct listed plan.
collision_path=$(cd "$UNRELATED_CWD" && PLAN_TIMESTAMP=2026-01-02-030405 "$PREPARE_PATH" --workspace "$linked" 'Detailed Plan!')
printf '%s\n' collision >"$source_plan"
assert_eq "$main/.agent/plans/2026-01-02-030405-detailed-plan--2.md" "$collision_path" 'plan path avoids collisions'
assert_empty_regular_file "$collision_path" 'second sequential plan path is reserved empty'
cp "$source_plan" "$collision_path"

third_collision_path=$(cd "$UNRELATED_CWD" && PLAN_TIMESTAMP=2026-01-02-030405 "$PREPARE_PATH" --workspace "$linked" 'Detailed Plan!')
assert_eq "$main/.agent/plans/2026-01-02-030405-detailed-plan--3.md" "$third_collision_path" 'sequential collisions retain increasing suffixes'
assert_empty_regular_file "$third_collision_path" 'third sequential plan path is reserved empty'

# Existing filesystem nodes remain untouched while allocation advances to the
# next collision suffix.
existing_base="$main/.agent/plans/2026-01-02-050607-existing-path.md"
existing_file_fixture="$TMPDIR_ROOT/existing-file-fixture"
symlink_target="$TMPDIR_ROOT/symlink-target"
printf 'existing file bytes\n' >"$existing_file_fixture"
cp "$existing_file_fixture" "$existing_base"
printf 'symlink target bytes\n' >"$symlink_target"
existing_symlink="$main/.agent/plans/2026-01-02-050607-existing-path--2.md"
ln -s "$symlink_target" "$existing_symlink"
existing_symlink_target=$(readlink "$existing_symlink")
existing_fifo="$main/.agent/plans/2026-01-02-050607-existing-path--3.md"
mkfifo "$existing_fifo"

existing_reserved_path=$(cd "$UNRELATED_CWD" && PLAN_TIMESTAMP=2026-01-02-050607 "$PREPARE_PATH" --workspace "$linked" existing-path)
assert_eq "$main/.agent/plans/2026-01-02-050607-existing-path--4.md" "$existing_reserved_path" 'existing filesystem nodes force the next suffix'
assert_empty_regular_file "$existing_reserved_path" 'post-existing-path reservation is empty and regular'
cmp -s "$existing_file_fixture" "$existing_base" || fail 'existing regular plan candidate must remain byte-identical'
printf '%s\n' 'ok - existing regular plan candidate remains byte-identical'
assert_eq "$existing_symlink_target" "$(readlink "$existing_symlink")" 'existing plan symlink keeps its target'
cmp -s "$symlink_target" "$existing_symlink" || fail 'existing plan symlink target must remain byte-identical'
printf '%s\n' 'ok - existing plan symlink target remains byte-identical'
[[ -p $existing_fifo ]] || fail 'existing plan FIFO must remain a FIFO'
printf '%s\n' 'ok - existing plan FIFO remains unchanged'

# Listing includes every regular valid plan and excludes all other direct nodes.
malformed_plan="$main/.agent/plans/not-a-plan.md"
plan_directory="$main/.agent/plans/2026-01-02-050607-plan-directory.md"
printf 'malformed\n' >"$malformed_plan"
mkdir "$plan_directory"
expected_listing=$(printf '%s\n' \
	"$collision_path" \
	"$third_collision_path" \
	"$prepared_path" \
	"$existing_reserved_path" \
	"$existing_base")
assert_eq "$expected_listing" "$(cd "$UNRELATED_CWD" && "$RESOLVE_PLAN" --workspace "$main")" 'primary checkout lists only valid regular plans in deterministic order'
assert_eq "$expected_listing" "$(cd "$UNRELATED_CWD" && "$RESOLVE_PLAN" --workspace "$linked")" 'linked checkout lists plans from shared canonical storage'

# Targeting repository B while the cwd is repository A accesses only B. Repo A
# (main) holds plans; repo B (empty_store) holds none, so a leaked cwd would
# surface main's plans instead of B's empty listing.
assert_eq "$empty_store" "$(cd "$main" && "$RESOLVER" --workspace "$empty_store")" 'resolver targets B while cwd is A'
assert_eq '' "$(cd "$main" && "$RESOLVE_PLAN" --workspace "$empty_store")" 'plan listing targets B while cwd is A'

# Concurrent callers with identical inputs each own a distinct empty reservation.
concurrent_results="$TMPDIR_ROOT/concurrent results"
mkdir "$concurrent_results"
concurrent_count=8
concurrent_pids=()
for ((index = 1; index <= concurrent_count; index += 1)); do
	(cd "$UNRELATED_CWD" && PLAN_TIMESTAMP=2026-01-02-060708 "$PREPARE_PATH" --workspace "$linked" concurrent-reservation) >"$concurrent_results/$index" &
	concurrent_pids+=("$!")
done
for pid in "${concurrent_pids[@]}"; do
	wait "$pid" || fail 'concurrent plan reservation must succeed'
done

concurrent_paths=()
for ((index = 1; index <= concurrent_count; index += 1)); do
	concurrent_path=$(<"$concurrent_results/$index")
	assert_empty_regular_file "$concurrent_path" "concurrent reservation $index is empty and regular"
	for prior_path in "${concurrent_paths[@]}"; do
		[[ $concurrent_path != "$prior_path" ]] || fail 'concurrent plan reservations must be unique'
	done
	concurrent_paths+=("$concurrent_path")
	printf 'reservation-%s\n' "$index" >"$concurrent_path"
done
printf '%s\n' 'ok - concurrent plan reservations are unique'

for ((index = 1; index <= concurrent_count; index += 1)); do
	concurrent_path=$(<"$concurrent_results/$index")
	assert_eq "reservation-$index" "$(<"$concurrent_path")" "concurrent reservation $index keeps isolated content"
done

# A creation failure without a competing reservation must fail instead of
# silently consuming collision suffixes forever.
plan_store="$main/.agent/plans"
creation_failure_stdout="$TMPDIR_ROOT/creation-failure-stdout"
creation_failure_stderr="$TMPDIR_ROOT/creation-failure-stderr"
chmod 500 "$plan_store"
set +e
(cd "$UNRELATED_CWD" && PLAN_TIMESTAMP=2026-01-02-080910 "$PREPARE_PATH" --workspace "$linked" creation-failure) >"$creation_failure_stdout" 2>"$creation_failure_stderr"
creation_failure_status=$?
set -e
chmod 700 "$plan_store"

assert_status 1 "$creation_failure_status" 'non-collision reservation failure is rejected'
[[ ! -s $creation_failure_stdout ]] || fail 'non-collision reservation failure must not print a path'
printf '%s\n' 'ok - non-collision reservation failure has no stdout'
assert_eq "prepare-path: could not reserve $plan_store/2026-01-02-080910-creation-failure.md" "$(<"$creation_failure_stderr")" 'non-collision reservation failure is diagnosed'

# Reusing a slug at another timestamp lists both plans for agent-side selection.
later_path=$(cd "$UNRELATED_CWD" && PLAN_TIMESTAMP=2026-01-02-040506 "$PREPARE_PATH" --workspace "$linked" 'Detailed Plan!')
cp "$source_plan" "$later_path"
assert_eq "$main/.agent/plans/2026-01-02-040506-detailed-plan.md" "$later_path" 'same slug can identify a later plan'
listed_plans=$(cd "$UNRELATED_CWD" && "$RESOLVE_PLAN" --workspace "$linked")
[[ $listed_plans == *"$prepared_path"* && $listed_plans == *"$later_path"* ]] || fail 'repeated slugs must all be listed'
printf '%s\n' 'ok - repeated slugs are all listed'

# Numeric slug components must not be mistaken for a --N collision suffix.
slug_two_path=$(cd "$UNRELATED_CWD" && PLAN_TIMESTAMP=2026-01-02-070809 "$PREPARE_PATH" --workspace "$linked" 'Detailed Plan 2')
cp "$source_plan" "$slug_two_path"
assert_eq "$slug_two_path" "$(cd "$UNRELATED_CWD" && "$RESOLVE_PLAN" --workspace "$linked" "$(basename "$slug_two_path")")" 'numeric exact filename validates'

assert_plan_failure "$linked" 2 'resolve-plan: invalid exact plan filename: detailed-plan' 'slug lookup is rejected' detailed-plan
assert_plan_failure "$linked" 2 'resolve-plan: invalid exact plan filename: 030405-detailed-plan.md' 'partial filename is rejected' 030405-detailed-plan.md
assert_plan_failure "$linked" 2 "$usage_diagnostic" 'unknown option is rejected' --latest
assert_plan_failure "$linked" 2 "$usage_diagnostic" 'extra argument is rejected' "$(basename "$prepared_path")" extra
assert_plan_failure "$linked" 1 'resolve-plan: plan is not a regular non-symlink file: 2026-01-02-030405-missing.md' 'missing exact filename is rejected' 2026-01-02-030405-missing.md
assert_plan_failure "$linked" 2 'resolve-plan: explicit plan path is outside the canonical store' 'outside-store path is rejected' "$source_plan"
assert_plan_failure "$main" 2 'resolve-plan: explicit plan path must be absolute: subdir/2026-01-02-030405-detailed-plan.md' 'relative explicit plan path is rejected' 'subdir/2026-01-02-030405-detailed-plan.md'

# Existing tracked content must never be converted into local ignored state.
tracked="$TMPDIR_ROOT/tracked store"
git init -q "$tracked"
mkdir -p "$tracked/.agent/plans"
printf '%s\n' tracked >"$tracked/.agent/plans/existing.md"
git -C "$tracked" add .agent/plans/existing.md
git -C "$tracked" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -qm tracked
set +e
(cd "$UNRELATED_CWD" && "$PREPARE_PATH" --workspace "$tracked" rejected >/dev/null 2>&1)
tracked_status=$?
set -e
assert_status 1 "$tracked_status" 'tracked plan store is rejected'
set +e
(cd "$UNRELATED_CWD" && "$RESOLVE_PLAN" --workspace "$tracked" existing.md >/dev/null 2>&1)
tracked_resolve_status=$?
set -e
assert_status 1 "$tracked_resolve_status" 'tracked plan cannot be resolved for maintenance'
set +e
(cd "$UNRELATED_CWD" && "$RESOLVE_PLAN" --workspace "$tracked" >/dev/null 2>&1)
tracked_listing_status=$?
set -e
assert_status 1 "$tracked_listing_status" 'tracked plan store cannot be listed'

# Store creation rejects pre-existing ignore rules it does not exclusively own.
malformed="$TMPDIR_ROOT/malformed ignore"
git init -q "$malformed"
git -C "$malformed" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q --allow-empty -m initial
mkdir -p "$malformed/.agent/plans"
printf '%s\n' '*.tmp' >"$malformed/.agent/plans/.gitignore"
set +e
(cd "$UNRELATED_CWD" && "$PREPARE_PATH" --workspace "$malformed" rejected >/dev/null 2>&1)
malformed_status=$?
set -e
assert_status 1 "$malformed_status" 'malformed plan ignore file is rejected'

# Resolution also rejects later edits that weaken the store-wide ignore rule.
printf '%s\n' '*' '!*.md' >"$main/.agent/plans/.gitignore"
set +e
(cd "$UNRELATED_CWD" && "$RESOLVE_PLAN" --workspace "$linked" "$(basename "$prepared_path")" >/dev/null 2>&1)
unignored_plan_status=$?
set -e
assert_status 1 "$unignored_plan_status" 'plan resolution rejects weakened ignore rules'
set +e
(cd "$UNRELATED_CWD" && "$RESOLVE_PLAN" --workspace "$linked" >/dev/null 2>&1)
unignored_listing_status=$?
set -e
assert_status 1 "$unignored_listing_status" 'plan listing rejects weakened ignore rules'
printf '*\n' >"$main/.agent/plans/.gitignore"

# Keep behavior-critical skill instructions covered alongside their helpers.
skill_content=$(<"$SCRIPT_DIR/../SKILL.md")
for required_text in \
	'Status: Ready | Blocked | Needs Reconciliation' \
	'## Before Starting' \
	'## Acceptance Criteria' \
	'## Final Validation' \
	'## Sources And Drift' \
	'Expected Plan Delta' \
	'Reconcile Only If' \
	'Baseline refresh' \
	'Expected plan delta' \
	'A change is material only when the executor can name the affected' \
	'Never add an empty section or' \
	'Do not infer persistence' \
	'Execution requires an explicit execute or run request' \
	'Immediately before writing, reread the plan' \
	'exact plan filename or path' \
	'list valid plans by running the resolver with no plan identifier' \
	'pass its exact path or filename back to the script for validation' \
	'no candidate is plausible or multiple candidates remain plausible' \
	'timestamp, mtime, listing order, lexical order, collision suffix'; do
	[[ $skill_content == *"$required_text"* ]] || fail "plan contract must contain: $required_text"
	printf 'ok - plan contract contains %s\n' "$required_text"
done

execute_content=${skill_content#*'### Execute'}
execute_content=${execute_content%%'### Update Or Reconcile'*}
for required_text in \
	'compare current state with both the planning' \
	'Stop only on plan-invalidating'; do
	[[ $execute_content == *"$required_text"* ]] || fail "execute contract must contain: $required_text"
	printf 'ok - execute contract contains %s\n' "$required_text"
done

update_content=${skill_content#*'### Update Or Reconcile'}
update_content=${update_content%%'## Method'*}
for required_text in \
	'compare current state with both the planning' \
	'Incorporate baseline refreshes and expected plan deltas'; do
	[[ $update_content == *"$required_text"* ]] || fail "update contract must contain: $required_text"
	printf 'ok - update contract contains %s\n' "$required_text"
done

output_content=${skill_content#*'## Output'}
output_content=${output_content%%'## Boundaries'*}
for required_text in \
	'optional when the work has no material content for them' \
	'Reference source entries instead of'; do
	[[ $output_content == *"$required_text"* ]] || fail "output contract must contain: $required_text"
	printf 'ok - output contract contains %s\n' "$required_text"
done
