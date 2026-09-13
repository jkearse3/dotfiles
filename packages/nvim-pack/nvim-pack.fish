function __fish_nvim_pack_plugins
    command nvim-pack list 2>/dev/null
end

complete -c nvim-pack -f
complete -c nvim-pack -s h -l help -d 'Show help'
complete -c nvim-pack -n __fish_use_subcommand -a list -d 'List active plugin names'
complete -c nvim-pack -n __fish_use_subcommand -a check -d 'Show available updates'
complete -c nvim-pack -n __fish_use_subcommand -a update -d 'Apply available updates'
complete -c nvim-pack -n __fish_use_subcommand -a prune -d 'Remove orphaned plugins'
complete -c nvim-pack -n '__fish_seen_subcommand_from list check update prune' -s h -l help -d 'Show help'
complete -c nvim-pack -n '__fish_seen_subcommand_from check' -a '(__fish_nvim_pack_plugins)' -d 'Active plugin'
complete -c nvim-pack -n '__fish_seen_subcommand_from update; and not __fish_contains_opt select' -a '(__fish_nvim_pack_plugins)' -d 'Active plugin'
complete -c nvim-pack -n '__fish_seen_subcommand_from update' -l select -d 'Choose from updatable plugins with fzf'
complete -c nvim-pack -n '__fish_seen_subcommand_from prune' -l dry-run -d 'List orphaned plugins without deleting them'
