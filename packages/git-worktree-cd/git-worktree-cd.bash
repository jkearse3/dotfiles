git-worktree-cd() {
	local worktree
	IFS= read -r -d '' worktree < <(git-worktree-select) && cd -- "$worktree"
}
