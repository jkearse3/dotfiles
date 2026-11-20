#!/usr/bin/env bash
# agent-store: locates and prepares the ignored `.agent/<name>` directory where
# agent tools keep local, per-repository state such as implement run records.
#
# Every Git worktree and jj workspace of a repository shares one store, kept in
# the main checkout: Git's main worktree, or jj's `default` workspace. The
# target repository always comes from --workspace, never from the caller's
# working directory.

set -euo pipefail

usage() {
	cat >&2 <<'EOF'
usage: agent-store root --workspace <absolute-workspace>
       agent-store dir --workspace <absolute-workspace> <name>

root  Print the main checkout whose .agent directory the workspace shares.
dir   Create .agent/<name> there if needed, ensure it is untracked and ignores
      everything it holds, and print its absolute path. <name> is lowercase
      letters, digits, and hyphens.

Exit status: 0 on success, 1 on failure, 2 on a usage error, 3 when several
jj workspaces exist and none is named default.
EOF
	exit 2
}

die() {
	printf 'agent-store: %s\n' "$1" >&2
	exit "${2:-1}"
}

# Prints the main checkout for an existing absolute workspace directory.
resolve_root() {
	local workspace=$1
	local field current_root default_root workspace_output
	local -a workspaces=()

	# Git lists its main worktree first, so linked worktrees share the main
	# checkout's store instead of creating separate stores.
	if command -v git >/dev/null 2>&1 && [[ $(git -C "$workspace" rev-parse --is-inside-work-tree 2>/dev/null) == true ]]; then
		while IFS= read -r -d '' field; do
			case $field in
			worktree\ *)
				printf '%s\n' "${field#worktree }"
				return 0
				;;
			esac
		done < <(git -C "$workspace" worktree list --porcelain -z)
		die 'Git did not report a main worktree'
	fi

	command -v jj >/dev/null 2>&1 || die 'not inside a Git worktree or jj workspace' 2
	current_root=$(jj --ignore-working-copy -R "$workspace" workspace root 2>/dev/null) ||
		die 'not inside a Git worktree or jj workspace' 2

	if default_root=$(jj --ignore-working-copy -R "$workspace" workspace root --name default 2>/dev/null); then
		printf '%s\n' "$default_root"
		return 0
	fi

	workspace_output=$(jj --ignore-working-copy -R "$workspace" workspace list -T 'name ++ "\n"' 2>/dev/null) ||
		die 'could not list jj workspaces'
	if [[ -n $workspace_output ]]; then
		mapfile -t workspaces <<<"$workspace_output"
	fi
	if [[ ${#workspaces[@]} -eq 1 ]]; then
		printf '%s\n' "$current_root"
		return 0
	fi
	die 'multiple jj workspaces exist without a default; choose a canonical workspace' 3
}

# Fails unless nothing under the root-relative path is tracked. The jj check
# reads the last recorded tree without snapshotting: the root may be another
# workspace whose working copy belongs to that workspace, and a file never
# snapshotted is not tracked. The fileset is root-relative because jj resolves a
# bare relative path against the caller's cwd rather than -R.
require_untracked() {
	local root=$1
	local relative=$2
	local tracked_files jj_err

	if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		tracked_files=$(git -C "$root" ls-files -- "$relative") ||
			die "could not inspect Git tracking for $relative"
	elif command -v jj >/dev/null 2>&1; then
		# jj warns on stderr when the path does not exist yet, which is the
		# normal first run; drop only that warning and pass any other output on.
		jj_err=$(mktemp)
		if ! tracked_files=$(jj --ignore-working-copy -R "$root" file list "root:\"$relative\"" 2>"$jj_err"); then
			cat "$jj_err" >&2
			rm -f "$jj_err"
			die "could not inspect jj tracking for $relative"
		fi
		grep -v '^Warning: No matching entries for paths:' "$jj_err" >&2 || true
		rm -f "$jj_err"
	else
		tracked_files=
	fi
	[[ -z $tracked_files ]] || die "$relative must be entirely untracked"
}

# Creates the store directory and an ignore file that ignores everything in it.
# An existing .gitignore is accepted when every non-empty, non-comment line is
# '*', so stored files always remain local.
ensure_ignored() {
	local root=$1
	local relative=$2
	local store="$root/$relative"
	local ignore="$store/.gitignore"
	local line ignore_ok

	mkdir -p "$store"
	if [[ -e $ignore ]]; then
		[[ -f $ignore ]] || die "$ignore must be a regular file ignoring '*'"
		ignore_ok=0
		while IFS= read -r line || [[ -n $line ]]; do
			[[ -z $line || $line == \#* ]] && continue
			if [[ $line == '*' ]]; then
				ignore_ok=1
			else
				ignore_ok=0
				break
			fi
		done <"$ignore"
		[[ $ignore_ok -eq 1 ]] || die "$ignore must ignore everything with '*'"
	else
		printf '*\n' >"$ignore"
	fi

	if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
		! git -C "$root" check-ignore -q "$relative/.gitignore"; then
		die "$relative is not ignored"
	fi
}

# Parse the whole command line before any repository discovery, so malformed
# input fails with a usage error.
command=${1:-}
[[ $command == root || $command == dir ]] || usage
shift
[[ ${1:-} == --workspace && $# -ge 2 ]] || usage
workspace=$2
shift 2
if [[ $command == root ]]; then
	[[ $# -eq 0 ]] || usage
else
	[[ $# -eq 1 ]] || usage
	name=$1
	[[ $name =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || usage
fi
[[ $workspace == /* ]] || usage
[[ -d $workspace ]] || die "workspace is not a directory: $workspace"
workspace=$(cd "$workspace" && pwd -P)

root=$(resolve_root "$workspace")
if [[ $command == root ]]; then
	printf '%s\n' "$root"
	exit 0
fi

relative=".agent/$name"
require_untracked "$root" "$relative"
ensure_ignored "$root" "$relative"
printf '%s\n' "$root/$relative"
