function __jj_worktree_add_revisions
    printf '@\tCurrent revision\n@-\tParent revision\n'
    jj bookmark list --ignore-working-copy -T 'if(!remote && present, name ++ "\n")' 2>/dev/null
end

complete -c jj-worktree-add -f
complete -c jj-worktree-add -s h -l help -d 'Show help'
complete -c jj-worktree-add -f -s r -r -d 'Revision revset' -a '(__jj_worktree_add_revisions)'
