#!/usr/bin/env bash

set -euo pipefail

jj_bookmark_push=$1
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

export HOME="$workdir/home"
mkdir -p "$HOME"

git init --bare -b main "$workdir/remote.git" >/dev/null
git init -b main "$workdir/repository" >/dev/null
git -C "$workdir/repository" config user.name "Test User"
git -C "$workdir/repository" config user.email test@example.com
printf 'initial\n' >"$workdir/repository/tracked"
git -C "$workdir/repository" add tracked
git -C "$workdir/repository" commit -m initial >/dev/null
git -C "$workdir/repository" branch feature-one
git -C "$workdir/repository" branch feature-two
git -C "$workdir/repository" remote add origin "$workdir/remote.git"
jj git init --colocate "$workdir/repository" >/dev/null

(
	cd "$workdir/repository"
	FZF_DEFAULT_OPTS='--filter=not-a-bookmark' "$jj_bookmark_push" --remote origin >/dev/null
)
[[ -z $(git --git-dir="$workdir/remote.git" for-each-ref refs/heads) ]]

selector_status=0
(
	cd "$workdir/repository"
	"$jj_bookmark_push" --all >/dev/null 2>"$workdir/selector-stderr"
) || selector_status=$?
[[ $selector_status -eq 2 ]]
grep -Fq 'push selector option is not supported: --all' "$workdir/selector-stderr"
[[ -z $(git --git-dir="$workdir/remote.git" for-each-ref refs/heads) ]]

fzf_status=0
(
	cd "$workdir/repository"
	FZF_DEFAULT_OPTS='--not-a-real-fzf-option' "$jj_bookmark_push" >/dev/null 2>"$workdir/fzf-stderr"
) || fzf_status=$?
[[ $fzf_status -eq 2 ]]
[[ -s $workdir/fzf-stderr ]]
[[ -z $(git --git-dir="$workdir/remote.git" for-each-ref refs/heads) ]]

(
	cd "$workdir/repository"
	FZF_DEFAULT_OPTS='--filter=feature-' "$jj_bookmark_push" --remote origin >/dev/null
)

mapfile -t pushed_bookmarks < <(
	git --git-dir="$workdir/remote.git" for-each-ref \
		--format='%(refname:short)' refs/heads | sort
)
[[ ${pushed_bookmarks[*]} == "feature-one feature-two" ]]
