complete -c direnv-worktree -f
complete -c direnv-worktree -s h -l help -d 'Show help'
complete -c direnv-worktree -n __fish_use_subcommand -a enable -d 'Enable automatic direnv preparation for linked worktrees'
complete -c direnv-worktree -n __fish_use_subcommand -a disable -d 'Disable automatic direnv preparation for linked worktrees'
complete -c direnv-worktree -n __fish_use_subcommand -a post-checkout -d "Handle Git's post-checkout hook"
complete -c direnv-worktree -n '__fish_seen_subcommand_from enable disable post-checkout' -s h -l help -d 'Show help'
