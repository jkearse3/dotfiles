#!/usr/bin/env bash
# Confirms and removes the jj workspace the current Herdr workspace shows
# with jjx workspace remove, then closes the Herdr workspace. Runs in a Herdr
# popup.

set -euo pipefail

fail() {
	printf 'error: %s\n\nPress enter to close.' "$1" >&2
	read -r _ || true
	exit 1
}

herdr=${HERDR_BIN_PATH:-herdr}
context=${HERDR_PLUGIN_CONTEXT_JSON:?}
workspace_id=$(jq -r '.workspace_id // empty' <<<"$context")
checkout=$(jq -r '.worktree.checkout_path // empty' <<<"$context")
repo_root=$(jq -r '.worktree.repo_root // empty' <<<"$context")
if [[ -z $workspace_id || -z $checkout ]]; then
	fail "the current Herdr workspace is not a Git worktree"
fi

# jjx refuses anything jj workspace add did not create, such as Git worktrees,
# which Herdr's remove_worktree handles instead.
if ! summary=$(jjx workspace remove --dry-run "$checkout"); then
	fail "nothing to remove here; see the output above"
fi
printf '%s\n\n' "$summary"
printf 'This deletes the directory and closes its Herdr workspace.\n'
printf 'jj snapshots its working copy into a commit first; ignored files are lost.\n\n'
read -r -p 'Remove? [y/N] ' answer
if [[ $answer != y && $answer != Y ]]; then
	exit 0
fi

# The repository's primary checkout workspace, focused once this one closes.
primary_workspace_id=$("$herdr" workspace list | jq -r --arg repo_root "$repo_root" '
	first(.result.workspaces[]
		| select(.worktree.repo_root == $repo_root and .worktree.is_linked_worktree == false)
		| .workspace_id) // empty' || true)

if ! jjx workspace remove "$checkout" >/dev/null; then
	fail "jjx workspace remove failed; see the output above"
fi
if ! "$herdr" workspace close "$workspace_id" >/dev/null; then
	fail "removed the jj workspace, but Herdr could not close workspace $workspace_id"
fi
# Focusing is a convenience; Herdr already moved focus somewhere usable.
if [[ -n $primary_workspace_id ]]; then
	"$herdr" workspace focus "$primary_workspace_id" >/dev/null || true
fi
