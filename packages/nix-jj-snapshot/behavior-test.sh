#!/usr/bin/env bash

# Tests when the nix-jj-snapshot wrapper snapshots the jj working copy and how
# it runs the real Nix. Usage: behavior-test.sh <wrapper whose real Nix is a
# stub>. The stub real Nix appends
# `nix [arg]...` to $NIX_JJ_SNAPSHOT_TEST_LOG, writes its HOME, or `<unset>`, to
# $NIX_JJ_SNAPSHOT_TEST_LOG.home, and prints `real nix output`; the
# stub `jj` this test writes appends `jj <args>` to the same log, so the log
# records which commands ran, in order.

set -uo pipefail

wrapper=$1

failures=0
work="$(mktemp -d)"
stub_bin="$work/stub-bin"
mkdir -p "$stub_bin"
export NIX_JJ_SNAPSHOT_TEST_LOG="$work/log"
unset NIX_SKIP_JJ_SNAPSHOT NIX_GET_COMPLETIONS

# The stub exits with $JJ_STUB_SNAPSHOT_STATUS from `util snapshot`, after
# printing $JJ_STUB_SNAPSHOT_ERROR, when set, to standard error. Its snapshot
# prints to standard output, which the wrapper must keep out of its own.
{
	echo "#!$(command -v bash)"
	cat <<'EOF'
echo "jj $*" >>"$NIX_JJ_SNAPSHOT_TEST_LOG"
if [[ $1 == util ]]; then
	echo "jj snapshot output"
	[[ -z ${JJ_STUB_SNAPSHOT_ERROR-} ]] || echo "$JJ_STUB_SNAPSHOT_ERROR" >&2
	exit "${JJ_STUB_SNAPSHOT_STATUS:-0}"
fi
EOF
} >"$stub_bin/jj"
chmod +x "$stub_bin/jj"

if command -v jj >/dev/null 2>&1; then
	echo "not ok - the base PATH must not provide jj, but has $(command -v jj)" >&2
	exit 1
fi
path_with_jj="$stub_bin:$PATH"
path_without_jj="$PATH"

# The wrapper treats a directory as inside a jj repository when it or an
# ancestor contains `.jj`; the cases below run from one of these directories.
repository="$work/repository"
repository_subdirectory="$repository/sub/dir"
outside_repository="$work/outside"
mkdir -p "$repository/.jj" "$repository_subdirectory" "$outside_repository"

# Runs `executable` with PATH set to `path` and the remaining arguments, and
# records its exit status in `status`, its standard output in `stdout`, its
# standard error in `stderr`, and the commands it ran in `log`.
run_wrapper() {
	local executable=$1
	local path=$2
	shift 2
	: >"$NIX_JJ_SNAPSHOT_TEST_LOG"
	stdout="$(PATH="$path" "$executable" "$@" 2>"$work/stderr")"
	status=$?
	stderr="$(<"$work/stderr")"
	log="$(<"$NIX_JJ_SNAPSHOT_TEST_LOG")"
}

# Checks that the last run exited with `expected_status`, printed exactly
# `expected_stdout`, and ran exactly the commands in `expected_log`.
expect_run() {
	local name=$1
	local expected_status=$2
	local expected_stdout=$3
	local expected_log=$4
	if [[ $status -eq $expected_status && $stdout == "$expected_stdout" && $log == "$expected_log" ]]; then
		echo "ok - $name"
	else
		echo "not ok - $name: status $status, stdout:" >&2
		printf '%s\n' "$stdout" "stderr:" "$stderr" "log:" "$log" >&2
		failures=$((failures + 1))
	fi
}

# Checks that the last run's standard error contains `expected_text`.
expect_stderr() {
	local name=$1
	local expected_text=$2
	if [[ $stderr == *"$expected_text"* ]]; then
		echo "ok - $name"
	else
		echo "not ok - $name: stderr lacks '$expected_text':" >&2
		printf '%s\n' "$stderr" >&2
		failures=$((failures + 1))
	fi
}

snapshot_then_nix="jj util snapshot --quiet
nix [build] [--no-link] [.#lint] [two words] []"

cd "$repository" || exit 1
run_wrapper "$wrapper" "$path_with_jj" build --no-link .#lint "two words" ""
expect_run "inside a jj repository, the wrapper snapshots and then runs Nix with identical arguments" \
	0 "real nix output" "$snapshot_then_nix"

cd "$repository_subdirectory" || exit 1
run_wrapper "$wrapper" "$path_with_jj" build --no-link .#lint "two words" ""
expect_run "below a jj repository's root, the wrapper snapshots and then runs Nix" \
	0 "real nix output" "$snapshot_then_nix"

cd "$outside_repository" || exit 1
run_wrapper "$wrapper" "$path_with_jj" build --no-link .#lint "two words" ""
expect_run "outside a jj repository, Nix runs without jj" \
	0 "real nix output" "nix [build] [--no-link] [.#lint] [two words] []"

cd "$repository" || exit 1
run_wrapper "$wrapper" "$path_without_jj" flake check
expect_run "without jj on PATH, Nix runs without a snapshot" \
	0 "real nix output" "nix [flake] [check]"

JJ_STUB_SNAPSHOT_STATUS=3 run_wrapper "$wrapper" "$path_with_jj" flake check
expect_run "a failed snapshot stops before Nix with the snapshot's status" \
	3 "" "jj util snapshot --quiet"
expect_stderr "a failed snapshot names the repository" "in $repository"
expect_stderr "a failed snapshot names the skip variable" "NIX_SKIP_JJ_SNAPSHOT=1"

JJ_STUB_SNAPSHOT_STATUS=1 JJ_STUB_SNAPSHOT_ERROR="Config error: stub configuration failure" \
	run_wrapper "$wrapper" "$path_with_jj" flake check
expect_run "a jj error inside a repository, such as a broken configuration, stops before Nix" \
	1 "" "jj util snapshot --quiet"
expect_stderr "a jj error inside a repository shows jj's message" "Config error: stub configuration failure"
expect_stderr "a jj error inside a repository names the skip variable" "NIX_SKIP_JJ_SNAPSHOT=1"

NIX_SKIP_JJ_SNAPSHOT=1 JJ_STUB_SNAPSHOT_STATUS=3 run_wrapper "$wrapper" "$path_with_jj" flake check
expect_run "NIX_SKIP_JJ_SNAPSHOT=1 runs Nix without jj" \
	0 "real nix output" "nix [flake] [check]"

NIX_SKIP_JJ_SNAPSHOT=0 run_wrapper "$wrapper" "$path_with_jj" build --no-link .#lint "two words" ""
expect_run "NIX_SKIP_JJ_SNAPSHOT other than 1 still snapshots" \
	0 "real nix output" "$snapshot_then_nix"

NIX_GET_COMPLETIONS=2 run_wrapper "$wrapper" "$path_with_jj" build .#
expect_run "a shell completion request runs Nix without a snapshot" \
	0 "real nix output" "nix [build] [.#]"

cd "$outside_repository" || exit 1
HOME="" run_wrapper "$wrapper" "$path_with_jj" flake check
home="$(<"$NIX_JJ_SNAPSHOT_TEST_LOG.home")"
if [[ $home == "<unset>" ]]; then
	echo "ok - an empty HOME, as nh sets through sudo on macOS, reaches Nix unset"
else
	echo "not ok - an empty HOME reaches Nix as '$home'" >&2
	failures=$((failures + 1))
fi

HOME="$work/home" run_wrapper "$wrapper" "$path_with_jj" flake check
home="$(<"$NIX_JJ_SNAPSHOT_TEST_LOG.home")"
if [[ $home == "$work/home" ]]; then
	echo "ok - a non-empty HOME reaches Nix unchanged"
else
	echo "not ok - HOME $work/home reaches Nix as '$home'" >&2
	failures=$((failures + 1))
fi

# A test cannot create a directory owned by another user without root, so the
# foreign repository's `.jj` is a symlink to `/`, which root owns; the wrapper's
# ownership test follows the symlink as it follows a real directory. As root,
# `/` is not foreign, so the case cannot run.
foreign_repository="$work/foreign-repository"
mkdir -p "$foreign_repository"
ln -s / "$foreign_repository/.jj"
if [[ -O / ]]; then
	echo "ok - # SKIP a repository owned by another user: the test runs as the owner of /"
else
	cd "$foreign_repository" || exit 1
	run_wrapper "$wrapper" "$path_with_jj" build --no-link .#lint "two words" ""
	expect_run "in a repository whose .jj belongs to another user, Nix runs without a snapshot" \
		0 "real nix output" "nix [build] [--no-link] [.#lint] [two words] []"
	expect_stderr "a skipped snapshot in another user's repository is explained" "belongs to another user"
fi

if [[ $failures -ne 0 ]]; then
	echo "$failures case(s) failed" >&2
	exit 1
fi
