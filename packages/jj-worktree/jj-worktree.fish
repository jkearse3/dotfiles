function __jj_worktree_bookmarks
    set -l operation (command jj --no-pager --color=never --at-op=@ --ignore-working-copy \
        op log --no-graph -n 1 -T id 2>/dev/null)
    test -n "$operation"; or return
    command jj --no-pager --color=never --at-op="$operation" bookmark list \
        -T 'if(remote, "", name ++ "\n")' 2>/dev/null
end

function __jj_worktree_names
    command jj-worktree list 2>/dev/null | string replace -r '\t.*$' ''
end

complete -c jj-worktree -f
complete -c jj-worktree -n __fish_use_subcommand -a init -d 'Install managed-root exclusion'
complete -c jj-worktree -n __fish_use_subcommand -a add -d 'Create a managed worktree'
complete -c jj-worktree -n __fish_use_subcommand -a attach -d 'Attach an external worktree'
complete -c jj-worktree -n __fish_use_subcommand -a path -d 'Print a managed worktree path'
complete -c jj-worktree -n __fish_use_subcommand -a list -d 'List managed worktrees'
complete -c jj-worktree -n __fish_use_subcommand -a remove -d 'Remove a managed worktree'
complete -c jj-worktree -n __fish_use_subcommand -s h -l help -d 'Show help'

complete -c jj-worktree -n '__fish_seen_subcommand_from init' -s h -l help -d 'Show help'
complete -c jj-worktree -n '__fish_seen_subcommand_from add' -s h -l help -d 'Show help'
complete -c jj-worktree -n '__fish_seen_subcommand_from add' -s r -l revision -r \
    -d 'Use a revision instead of bookmark NAME'
complete -c jj-worktree -n '__fish_seen_subcommand_from add' -a '(__jj_worktree_bookmarks)'
complete -c jj-worktree -n '__fish_seen_subcommand_from attach' -s h -l help -d 'Show help'
complete -c jj-worktree -n '__fish_seen_subcommand_from attach' -F
complete -c jj-worktree -n '__fish_seen_subcommand_from path list remove' \
    -a '(__jj_worktree_names)'
complete -c jj-worktree -n '__fish_seen_subcommand_from path' -s h -l help -d 'Show help'
complete -c jj-worktree -n '__fish_seen_subcommand_from list' -s h -l help -d 'Show help'
complete -c jj-worktree -n '__fish_seen_subcommand_from remove' -s h -l help -d 'Show help'
complete -c jj-worktree -n '__fish_seen_subcommand_from remove' -l yes \
    -d 'Confirm destructive removal'
