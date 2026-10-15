#!/usr/bin/env bash
# Prompts for a name, creates a jj workspace for the current Herdr workspace's
# repository with jjx workspace add, and opens it in Herdr next to the
# repository's other worktrees. Runs in a Herdr popup.

set -euo pipefail

# Herdr's default worktree directory, which also holds its own worktrees.
WORKTREES_DIRECTORY="$HOME/.herdr/worktrees"

fail() {
	printf 'error: %s\n\nPress enter to close.' "$1" >&2
	read -r _ || true
	exit 1
}

herdr=${HERDR_BIN_PATH:-herdr}
workspace_id=$(jq -r '.workspace_id // empty' <<<"${HERDR_PLUGIN_CONTEXT_JSON:?}")
if [[ -z $workspace_id ]]; then
	fail "Herdr reported no current workspace"
fi
# Herdr resolves the workspace's repository from its checkout or pane
# directory, including workspaces it has not yet marked as Git workspaces.
if ! source=$("$herdr" worktree list --workspace "$workspace_id"); then
	fail "the current Herdr workspace is not in a Git repository"
fi
repo_root=$(jq -r '.result.source.repo_root // empty' <<<"$source")
repo_name=$(jq -r '.result.source.repo_name // empty' <<<"$source")
if [[ -z $repo_root || -z $repo_name ]]; then
	fail "Herdr reported no repository for the current workspace"
fi
if [[ ! -d $repo_root/.jj ]]; then
	fail "$repo_root has no jj repository; run jjx ensure there first"
fi

printf 'New jj workspace for %s\n\n' "$repo_name"
read -r -p 'Name: ' name
if [[ -z $name || $name == . || $name == .. || $name == -* || $name == */* ]]; then
	fail "the name must be one path component that does not start with -"
fi
destination="$WORKTREES_DIRECTORY/$repo_name/$name"
if [[ -e $destination ]]; then
	fail "$destination already exists"
fi
mkdir -p "$(dirname "$destination")"

# Start from trunk rather than the primary checkout's @, so a new workspace never
# builds on another workspace's unfinished work.
if ! root=$(cd "$repo_root" && jjx workspace add --name "$name" --revision 'trunk()' -- "$destination"); then
	fail "jjx workspace add failed; see the output above"
fi
# Opening from the current workspace groups the new one under it, as Herdr's
# own new_worktree does.
if ! "$herdr" worktree open --workspace "$workspace_id" --path "$root" --focus >/dev/null; then
	fail "created $root, but Herdr could not open it"
fi
