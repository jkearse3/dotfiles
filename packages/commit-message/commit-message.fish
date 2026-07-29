complete -c commit-message -f
complete -c commit-message -s h -l help -d 'Show help'
complete -c commit-message -n __fish_use_subcommand -a format -d 'Format a commit description'
complete -c commit-message -n __fish_use_subcommand -a check -d 'Check a commit description'
complete -c commit-message -n '__fish_seen_subcommand_from format' -s h -l help -d 'Show help'
complete -c commit-message -n '__fish_seen_subcommand_from format' -l body-width -x -d 'Maximum body/footer line width'
complete -c commit-message -n '__fish_seen_subcommand_from check' -s h -l help -d 'Show help'
complete -c commit-message -n '__fish_seen_subcommand_from check' -l subject-width -x -d 'Maximum subject width'
complete -c commit-message -n '__fish_seen_subcommand_from check' -l body-width -x -d 'Maximum body/footer line width'
