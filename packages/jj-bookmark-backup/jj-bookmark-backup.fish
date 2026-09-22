function __jj_bookmark_backup_bookmarks
    jj bookmark list --ignore-working-copy --all-remotes -T 'if(present, name ++ "\n")' 2>/dev/null | sort -u
end

function __jj_bookmark_backup_remotes
    jj git remote list --ignore-working-copy 2>/dev/null | while read -l remote url
        echo $remote
    end
end

function __jj_bookmark_backup_needs_bookmark
    set -l consume_remote 0
    for token in (commandline -opc)[2..-1]
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

complete -c jj-bookmark-backup -f
complete -c jj-bookmark-backup -s h -l help -d 'Show help'
complete -c jj-bookmark-backup -l remote -r -f -d 'Source remote' -a '(__jj_bookmark_backup_remotes)'
complete -c jj-bookmark-backup -n __jj_bookmark_backup_needs_bookmark -f -d 'Bookmark to back up' -a '(__jj_bookmark_backup_bookmarks)'
