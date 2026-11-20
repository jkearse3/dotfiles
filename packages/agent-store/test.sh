#!/usr/bin/env bash
# Tests the agent-store on PATH against real Git and jj repositories.

set -euo pipefail

AGENT_STORE=agent-store

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
for tool in agent-store git jj; do
	command -v "$tool" >/dev/null 2>&1 || fail "$tool is required on PATH"
done

TMPDIR_ROOT=$(mktemp -d)
TMPDIR_ROOT=$(cd "$TMPDIR_ROOT" && pwd -P)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Isolate jj from the user's configuration. Git identity is passed per command.
export JJ_CONFIG="$TMPDIR_ROOT/jj-config.toml"
cat >"$JJ_CONFIG" <<'EOF'
user.name = "Test"
user.email = "test@example.com"
EOF

# Every call passes an explicit --workspace, so run the suite from a directory
# unrelated to any fixture to prove the target never comes from the caller's
# working directory.
OUTSIDE="$TMPDIR_ROOT/outside cwd"
mkdir -p "$OUTSIDE"
cd "$OUTSIDE"

git_test() {
	git -c user.name=Test -c user.email=test@example.com "$@"
}

# Runs agent-store and records its stdout, stderr, and exit status in
# store_out, store_err, and store_status.
run_store() {
	local err_file="$TMPDIR_ROOT/store.err"

	set +e
	store_out=$("$AGENT_STORE" "$@" 2>"$err_file")
	store_status=$?
	set -e
	store_err=$(<"$err_file")
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

# Preparing from a non-default workspace must not snapshot the default
# workspace, whose working copy that workspace owns. This runs first on a fresh
# fixture so no earlier jj command has snapshotted the untracked file.
fresh="$TMPDIR_ROOT/fresh jj"
make_jj_non_colocated "$fresh"
printf '%s\n' untracked >"$fresh/default/untracked.txt"
operations_before=$(count_operations "$fresh/default")
run_store dir --workspace "$fresh/second" tool
assert_status 0 "$store_status" 'store from a jj workspace succeeds'
assert_eq "$operations_before" "$(count_operations "$fresh/default")" 'preparing does not snapshot another workspace'

# Fixture N resolves to the default workspace and keeps stored files untracked.
non_colocated="$TMPDIR_ROOT/non colocated"
make_jj_non_colocated "$non_colocated"
run_store root --workspace "$non_colocated/second"
assert_eq "$non_colocated/default" "$store_out" 'non-colocated jj root is the default workspace'
run_store dir --workspace "$non_colocated/second" tool
assert_status 0 "$store_status" 'non-colocated jj store succeeds'
assert_lacks 'No matching entries' "$store_err" 'non-colocated jj store prints no jj path warning'
assert_eq "$non_colocated/default/.agent/tool" "$store_out" 'non-colocated jj store is under the default workspace'
assert_eq '*' "$(<"$store_out/.gitignore")" 'store ignores all contents'
printf '%s\n' state >"$store_out/state.md"
assert_jj_untracked 'non-colocated jj' "$non_colocated/default" "$non_colocated/second"
run_store dir --workspace "$non_colocated/default" tool
assert_status 0 "$store_status" 'preparing an existing store succeeds'
assert_eq state "$(<"$store_out/state.md")" 'preparing an existing store keeps its contents'

# Fixture C resolves through Git to the main worktree.
colocated="$TMPDIR_ROOT/colocated"
make_jj_colocated "$colocated"
run_store dir --workspace "$colocated/second" tool
assert_status 0 "$store_status" 'colocated jj store succeeds'
assert_eq "$colocated/default/.agent/tool" "$store_out" 'colocated jj store is under the main worktree'
printf '%s\n' state >"$store_out/state.md"
assert_jj_untracked 'colocated jj' "$colocated/default" "$colocated/second"

# Fixture G resolves to the main worktree and keeps stored files out of status.
plain="$TMPDIR_ROOT/plain git"
make_git "$plain"
run_store root --workspace "$plain/linked"
assert_eq "$plain/main" "$store_out" 'Git root is the main worktree'
run_store dir --workspace "$plain/linked" tool
assert_eq "$plain/main/.agent/tool" "$store_out" 'Git store is under the main worktree'
printf '%s\n' state >"$store_out/state.md"
assert_eq '' "$(git -C "$plain/main" status --porcelain)" 'Git main worktree status lists no stored files'
assert_eq '' "$(git -C "$plain/linked" status --porcelain)" 'Git linked worktree status lists no stored files'

# The caller's working directory, here a different repository, never selects
# the store.
cross_out=$(cd "$plain/main" && "$AGENT_STORE" dir --workspace "$non_colocated/second" tool)
assert_eq "$non_colocated/default/.agent/tool" "$cross_out" 'store follows --workspace, not the caller cwd'

# Fixture A: no workspace is named default, so the store is ambiguous.
ambiguous="$TMPDIR_ROOT/ambiguous"
make_jj_non_colocated "$ambiguous"
jj -R "$ambiguous/default" workspace rename renamed >/dev/null 2>&1
run_store dir --workspace "$ambiguous/second" tool
assert_status 3 "$store_status" 'ambiguous store is rejected'
assert_eq '' "$store_out" 'ambiguous store prints no path'
[[ ! -e $ambiguous/default/.agent && ! -e $ambiguous/second/.agent ]] ||
	fail 'ambiguous store creates no directory'
printf '%s\n' 'ok - ambiguous store creates no directory'

# A store tracked by Git is refused.
git_tracked="$TMPDIR_ROOT/git tracked"
make_git "$git_tracked"
mkdir -p "$git_tracked/main/.agent/tool"
printf '%s\n' tracked >"$git_tracked/main/.agent/tool/existing.md"
git -C "$git_tracked/main" add .agent/tool/existing.md
git_test -C "$git_tracked/main" commit -qm tracked
run_store dir --workspace "$git_tracked/linked" tool
assert_status 1 "$store_status" 'Git-tracked store is rejected'
assert_contains 'must be entirely untracked' "$store_err" 'Git-tracked store reports the reason'

# A store committed in jj is refused, even when checked from another workspace
# and from an unrelated cwd, which requires a root-relative fileset.
jj_tracked="$TMPDIR_ROOT/jj tracked"
make_jj_non_colocated "$jj_tracked"
mkdir -p "$jj_tracked/default/.agent/tool"
printf '%s\n' tracked >"$jj_tracked/default/.agent/tool/existing.md"
jj -R "$jj_tracked/default" commit -m tracked >/dev/null 2>&1
run_store dir --workspace "$jj_tracked/second" tool
assert_status 1 "$store_status" 'jj-tracked store is rejected'
assert_contains 'must be entirely untracked' "$store_err" 'jj-tracked store reports the reason'

# A store .gitignore that does not ignore everything is refused.
partial_ignore="$TMPDIR_ROOT/partial ignore"
make_git "$partial_ignore"
mkdir -p "$partial_ignore/main/.agent/tool"
printf '%s\n' '*' '*.tmp' >"$partial_ignore/main/.agent/tool/.gitignore"
run_store dir --workspace "$partial_ignore/main" tool
assert_status 1 "$store_status" 'partial store ignore file is rejected'
assert_contains "must ignore everything with '*'" "$store_err" 'partial store ignore file reports the reason'

# CLI validation: usage errors exit 2 with empty stdout before any discovery.
run_store
assert_status 2 "$store_status" 'a missing command is rejected'
assert_eq '' "$store_out" 'a missing command prints no stdout'
run_store bogus --workspace "$plain/main"
assert_status 2 "$store_status" 'an unknown command is rejected'
run_store dir --workspace
assert_status 2 "$store_status" '--workspace without a value is rejected'
run_store dir --workspace "$plain/main"
assert_status 2 "$store_status" 'dir without a name is rejected'
run_store dir --workspace "$plain/main" ../escape
assert_status 2 "$store_status" 'a name with path characters is rejected'
run_store dir --workspace "$plain/main" Tool
assert_status 2 "$store_status" 'a name with uppercase letters is rejected'
run_store root --workspace "$plain/main" extra
assert_status 2 "$store_status" 'root with extra arguments is rejected'
run_store dir --workspace relative/path tool
assert_status 2 "$store_status" 'a relative workspace is rejected'
run_store dir --workspace "$TMPDIR_ROOT/does not exist" tool
assert_status 1 "$store_status" 'a nonexistent workspace is rejected'
assert_eq '' "$store_out" 'a nonexistent workspace prints no stdout'
not_repo="$TMPDIR_ROOT/not a repo"
mkdir -p "$not_repo"
run_store root --workspace "$not_repo"
assert_status 2 "$store_status" 'a directory outside any repository is rejected'
assert_contains 'not inside a Git worktree or jj workspace' "$store_err" 'outside a repository reports the reason'

# A path that exists but is not a directory is an operational error.
not_dir="$TMPDIR_ROOT/a file"
: >"$not_dir"
run_store root --workspace "$not_dir"
assert_status 1 "$store_status" 'a non-directory workspace is rejected'
assert_eq '' "$store_out" 'a non-directory workspace prints no stdout'

# A bare Git repository has no worktree to hold a store.
bare="$TMPDIR_ROOT/bare repo.git"
git init -q --bare "$bare"
run_store root --workspace "$bare"
assert_status 2 "$store_status" 'a bare Git repository is rejected'

# A colocated repository resolves through Git without consulting jj.
(
	# Invoked indirectly by the agent-store child process.
	# shellcheck disable=SC2329
	jj() {
		printf 'jj ran for a colocated repository\n' >&2
		return 1
	}
	export -f jj
	run_store root --workspace "$colocated/second"
	assert_eq "$colocated/default" "$store_out" 'a colocated repository resolves through Git alone'
)

# A failure to inspect tracking is reported instead of assumed untracked.
(
	# Invoked indirectly by the agent-store child process.
	# shellcheck disable=SC2329
	git() {
		case "$*" in
		*ls-files*)
			return 1
			;;
		*)
			command git "$@"
			;;
		esac
	}
	export -f git
	run_store dir --workspace "$plain/main" inspection
	assert_status 1 "$store_status" 'a Git tracking inspection failure is rejected'
	assert_contains 'could not inspect Git tracking' "$store_err" 'a Git tracking inspection failure reports the reason'
)

# A pure jj workspace whose `file list` fails is likewise rejected; the mock jj
# resolves the workspace to itself and fails every other query.
jj_inspection="$TMPDIR_ROOT/jj inspection"
mkdir -p "$jj_inspection"
(
	# Invoked indirectly by the agent-store child process.
	# shellcheck disable=SC2329
	git() {
		return 1
	}
	# shellcheck disable=SC2329
	jj() {
		case "$1:$2:${4:-}:${5:-}" in
		--ignore-working-copy:-R:workspace:root)
			printf '%s\n' "$JJ_INSPECTION_ROOT"
			;;
		*)
			return 1
			;;
		esac
	}
	export JJ_INSPECTION_ROOT=$jj_inspection
	export -f git jj
	run_store dir --workspace "$jj_inspection" inspection
	assert_status 1 "$store_status" 'a jj tracking inspection failure is rejected'
	assert_contains 'could not inspect jj tracking' "$store_err" 'a jj tracking inspection failure reports the reason'
)

# jj discovery edge cases, with jj replaced by a mock that answers only the
# queries agent-store makes: `--ignore-working-copy -R <workspace> workspace
# root|list ...`.
mock_ws="$TMPDIR_ROOT/mock ws"
mkdir -p "$mock_ws"

run_mock_jj() (
	local mode=$1
	local expected_status=$2
	local expected_output=$3

	# Invoked indirectly by the agent-store child process.
	# shellcheck disable=SC2329
	git() {
		return 1
	}
	# shellcheck disable=SC2329
	jj() {
		if [[ $1 != --ignore-working-copy || $2 != -R || $4 != workspace ]]; then
			return 1
		fi

		case "$MODE:$5:${6:-}" in
		default:root:)
			printf '%s\n' '/work/current'
			;;
		default:root:--name)
			printf '%s\n' '/work/default'
			;;
		sole:root:)
			printf '%s\n' '/work/sole'
			;;
		sole:list:-T)
			printf 'solo\n'
			;;
		ambiguous:root:)
			printf '%s\n' '/work/current'
			;;
		ambiguous:list:-T)
			printf 'one\ntwo\n'
			;;
		*)
			return 1
			;;
		esac
	}
	export MODE=$mode
	export -f git jj

	run_store root --workspace "$mock_ws"
	assert_status "$expected_status" "$store_status" "mock jj $mode status"
	assert_eq "$expected_output" "$store_out" "mock jj $mode result"
)

run_mock_jj default 0 /work/default
run_mock_jj sole 0 /work/sole
run_mock_jj ambiguous 3 ''
run_mock_jj outside 2 ''
