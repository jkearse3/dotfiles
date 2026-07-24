function git-worktree-cd --description 'Change to a Git worktree selected with fzf'
    set -l worktree (git-worktree-select | string split0)
    test (count $worktree) -eq 1; and cd "$worktree"
end
