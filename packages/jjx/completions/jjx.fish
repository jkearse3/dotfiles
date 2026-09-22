function __jjx_needs_subcommand
    set -l group $argv[1]
    set -l tokens (commandline -opc)
    test (count $tokens) -eq 2; and test $tokens[2] = $group
end

function __jjx_using
    set -l tokens (commandline -opc)
    set -e tokens[1]
    for index in (seq (count $argv))
        test "$tokens[$index]" = "$argv[$index]"; or return 1
    end
end

function __jjx_bookmarks
    jj bookmark list --ignore-working-copy -T 'if(!remote && present, name ++ "\n")' 2>/dev/null
end

function __jjx_all_bookmarks
    jj bookmark list --ignore-working-copy --all-remotes -T 'if(present, name ++ "\n")' 2>/dev/null | sort -u
end

function __jjx_remotes
    jj git remote list --ignore-working-copy 2>/dev/null | while read -l remote url
        echo $remote
    end
end

function __jjx_revisions
    printf '@\tCurrent revision\n@-\tParent revision\n'
    __jjx_bookmarks
end

function __jjx_backup_needs_bookmark
    set -l consume_remote 0
    for token in (commandline -opc)[4..-1]
        if test $consume_remote -eq 1
            set consume_remote 0
            continue
        end

        switch $token
            case --remote
                set consume_remote 1
            case '--remote=*' '-*'
            case '*'
                return 1
        end
    end
    return 0
end

function __jjx_needs_third_level_argument
    set -l tokens (commandline -opc)
    test (count $tokens) -eq 3
end

function __jjx_ensure_needs_path
    set -l tokens (commandline -opc)
    for token in $tokens[3..-1]
        switch $token
            case -h --help --dry-run
            case '*'
                return 1
        end
    end
    return 0
end

function __jjx_land_needs_tip
    set -l tokens (commandline -opc)
    argparse --ignore-unknown 'd/destination=' forget dry-run -- $tokens[4..] 2>/dev/null
    and test (count $argv) -eq 0
end

function __jjx_needs_group
    set -l tokens (commandline -opc)
    test (count $tokens) -eq 1
end

complete -c jjx -f
complete -c jjx -s h -l help -d 'Show help'
complete -c jjx -n __jjx_needs_group -a bookmark -d 'Commands for bookmarks'
complete -c jjx -n __jjx_needs_group -a change -d 'Commands for changes'
complete -c jjx -n __jjx_needs_group -a description -d 'Commands for descriptions'
complete -c jjx -n __jjx_needs_group -a ensure -d 'Ensure a Git checkout has compatible jj state'
complete -c jjx -n __jjx_needs_group -a worktree -d 'Commands for Git worktrees'

complete -c jjx -n '__jjx_needs_subcommand bookmark' -a backup -d 'Preserve remote bookmark history locally'
complete -c jjx -n '__jjx_needs_subcommand bookmark' -a current -d 'Print the nearest current bookmark'
complete -c jjx -n '__jjx_needs_subcommand bookmark' -a default -d 'Print the trunk bookmark'
complete -c jjx -n '__jjx_needs_subcommand bookmark' -a land -d 'Land a linear bookmark stack'
complete -c jjx -n '__jjx_needs_subcommand bookmark' -a nearest -d 'Query nearest matching bookmarks'
complete -c jjx -n '__jjx_needs_subcommand bookmark' -a previous -d 'Print the previous stacked bookmark'
complete -c jjx -n '__jjx_needs_subcommand bookmark' -a push -d 'Interactively push bookmarks'
complete -c jjx -n '__jjx_needs_subcommand bookmark' -a rebase -d 'Interactively rebase bookmarks'
complete -c jjx -n '__jjx_needs_subcommand bookmark' -a select -d 'Interactively select a bookmark'
complete -c jjx -n '__jjx_needs_subcommand bookmark' -a stacked -d 'List bookmarks from the current change to trunk'
complete -c jjx -n '__jjx_needs_subcommand change' -a select -d 'Interactively select a change'
complete -c jjx -n '__jjx_needs_subcommand description' -a format -d 'Format a revision description'
complete -c jjx -n '__jjx_needs_subcommand worktree' -a add -d 'Create a detached Git worktree with independent jj state'


# Every leaf accepts help; leaf-specific declarations below add its full argument surface.
complete -c jjx -n '__jjx_using bookmark backup; or __jjx_using bookmark current; or __jjx_using bookmark default; or __jjx_using bookmark land; or __jjx_using bookmark nearest; or __jjx_using bookmark previous; or __jjx_using bookmark push; or __jjx_using bookmark rebase; or __jjx_using bookmark select; or __jjx_using bookmark stacked; or __jjx_using change select; or __jjx_using description format; or __jjx_using ensure; or __jjx_using worktree add' -s h -l help -d 'Show help'

complete -c jjx -n '__jjx_using bookmark nearest; and __jjx_needs_third_level_argument' -f -d 'Revset to search' -a '(__jjx_revisions)'
complete -c jjx -n '__jjx_using bookmark rebase; and __jjx_needs_third_level_argument' -f -d 'Destination revset' -a '(__jjx_revisions)'

# Push forwards non-selector jj git push options. Selection flags are intentionally absent.
complete -c jjx -n '__jjx_using bookmark push' -l remote -r -f -a '(__jjx_remotes)' -d 'Remote to push to'
complete -c jjx -n '__jjx_using bookmark push' -l allow-empty-description -d 'Allow empty descriptions'
complete -c jjx -n '__jjx_using bookmark push' -l allow-private -d 'Allow private commits'
complete -c jjx -n '__jjx_using bookmark push' -l allow-conflicts -d 'Allow conflicted commits'
complete -c jjx -n '__jjx_using bookmark push' -l dry-run -d 'Show changes without pushing'
complete -c jjx -n '__jjx_using bookmark push' -s o -l option -r -d 'Git push option'
complete -c jjx -n '__jjx_using bookmark push' -s R -l repository -r -F -d 'Repository path'
complete -c jjx -n '__jjx_using bookmark push' -l ignore-working-copy -d 'Do not snapshot the working copy'
complete -c jjx -n '__jjx_using bookmark push' -l no-integrate-operation -d 'Do not integrate the operation'
complete -c jjx -n '__jjx_using bookmark push' -l ignore-immutable -d 'Allow rewriting immutable commits'
complete -c jjx -n '__jjx_using bookmark push' -l at-operation -r -d 'Operation to load'
complete -c jjx -n '__jjx_using bookmark push' -l at-op -r -d 'Operation to load'
complete -c jjx -n '__jjx_using bookmark push' -l debug -d 'Enable debug logging'
complete -c jjx -n '__jjx_using bookmark push' -l color -r -a 'always never debug auto' -d 'Color mode'
complete -c jjx -n '__jjx_using bookmark push' -l quiet -d 'Silence non-primary output'
complete -c jjx -n '__jjx_using bookmark push' -l no-pager -d 'Disable the pager'
complete -c jjx -n '__jjx_using bookmark push' -l config -r -d 'Additional configuration'
complete -c jjx -n '__jjx_using bookmark push' -l config-file -r -F -d 'Additional configuration file'
complete -c jjx -n '__jjx_using bookmark backup' -l remote -r -f -d 'Source remote' -a '(__jjx_remotes)'
complete -c jjx -n '__jjx_using bookmark backup; and __jjx_backup_needs_bookmark' -f -d 'Bookmark to back up' -a '(__jjx_all_bookmarks)'

complete -c jjx -n '__jjx_using bookmark land' -s d -l destination -r -f -d 'Destination bookmark' -a '(__jjx_bookmarks)'
complete -c jjx -n '__jjx_using bookmark land' -l forget -d 'Forget landed bookmarks'
complete -c jjx -n '__jjx_using bookmark land' -l dry-run -d 'Show the landing plan'
complete -c jjx -n '__jjx_using bookmark land; and __jjx_land_needs_tip' -a '(__jjx_bookmarks)' -d 'Stack-tip bookmark'

complete -c jjx -n '__jjx_using description format' -s r -l revision -r -f -d 'Target revision' -a '(__jjx_revisions)'
complete -c jjx -n '__jjx_using description format' -l dry-run -d 'Show the diff without writing'
complete -c jjx -n '__jjx_using description format' -l subject-width -r -f -d 'Maximum subject width'
complete -c jjx -n '__jjx_using description format' -l body-width -r -f -d 'Maximum body line width'

complete -c jjx -n '__jjx_using ensure' -l dry-run -d 'Show the validated action without modifying the workspace'
complete -c jjx -n '__jjx_using ensure; and __jjx_ensure_needs_path' -F

complete -c jjx -n '__jjx_using worktree add' -f -s r -r -d 'Revision revset' -a '(__jjx_revisions)'
