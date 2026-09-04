#!/usr/bin/env bash

set -euo pipefail

jj_bookmark_rebase=$1
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

export HOME="$workdir/home"
mkdir -p "$HOME"

# Build main -> feature-one, main -> feature-two, and main -> release#1 (a
# name jj must quote as a revset symbol), then advance main so all three are
# stale.
git init -b main "$workdir/repository" >/dev/null
git -C "$workdir/repository" config user.name "Test User"
git -C "$workdir/repository" config user.email test@example.com
printf 'initial\n' >"$workdir/repository/tracked"
git -C "$workdir/repository" add tracked
git -C "$workdir/repository" commit -m initial >/dev/null
git -C "$workdir/repository" branch feature-one
git -C "$workdir/repository" branch feature-two
git -C "$workdir/repository" branch 'release#1'
git -C "$workdir/repository" checkout -q feature-one
printf 'one\n' >"$workdir/repository/one"
git -C "$workdir/repository" add one
git -C "$workdir/repository" commit -m one >/dev/null
git -C "$workdir/repository" checkout -q feature-two
printf 'two\n' >"$workdir/repository/two"
git -C "$workdir/repository" add two
git -C "$workdir/repository" commit -m two >/dev/null
git -C "$workdir/repository" checkout -q 'release#1'
printf 'release\n' >"$workdir/repository/release"
git -C "$workdir/repository" add release
git -C "$workdir/repository" commit -m release >/dev/null
git -C "$workdir/repository" checkout -q main
printf 'advanced\n' >"$workdir/repository/advanced"
git -C "$workdir/repository" add advanced
git -C "$workdir/repository" commit -m advanced >/dev/null
jj git init --colocate "$workdir/repository" >/dev/null

bookmark_parent() {
	jj -R "$workdir/repository" log --no-graph -r "bookmarks(exact:\"$1\")-" -T 'local_bookmarks'
}
[[ $(bookmark_parent feature-one) != main ]]
[[ $(bookmark_parent feature-two) != main ]]
[[ $(bookmark_parent 'release#1') != main ]]

(
	cd "$workdir/repository"
	FZF_DEFAULT_OPTS='--filter=not-a-bookmark' "$jj_bookmark_rebase" main >/dev/null
)
[[ $(bookmark_parent feature-one) != main ]]
[[ $(bookmark_parent feature-two) != main ]]

usage_status=0
(
	cd "$workdir/repository"
	FZF_DEFAULT_OPTS='--filter=feature-one' "$jj_bookmark_rebase" main extra >/dev/null 2>"$workdir/usage-stderr"
) || usage_status=$?
[[ $usage_status -eq 2 ]]
grep -Fq 'usage: jj-bookmark-rebase [DESTINATION]' "$workdir/usage-stderr"
[[ $(bookmark_parent feature-one) != main ]]

fzf_status=0
(
	cd "$workdir/repository"
	FZF_DEFAULT_OPTS='--not-a-real-fzf-option' "$jj_bookmark_rebase" main >/dev/null 2>"$workdir/fzf-stderr"
) || fzf_status=$?
[[ $fzf_status -eq 2 ]]
[[ -s $workdir/fzf-stderr ]]
[[ $(bookmark_parent feature-one) != main ]]

# Without a destination argument, the first picker yields main (first match in
# input order) and the second picker, which no longer lists main, yields
# release#1.
(
	cd "$workdir/repository"
	FZF_DEFAULT_OPTS="--no-sort --filter='main | release'" "$jj_bookmark_rebase" >/dev/null
)
[[ $(bookmark_parent 'release#1') == main ]]
[[ $(bookmark_parent feature-one) != main ]]
[[ $(bookmark_parent feature-two) != main ]]

(
	cd "$workdir/repository"
	FZF_DEFAULT_OPTS='--filter=feature-' "$jj_bookmark_rebase" main >/dev/null
)
[[ $(bookmark_parent feature-one) == main ]]
[[ $(bookmark_parent feature-two) == main ]]
