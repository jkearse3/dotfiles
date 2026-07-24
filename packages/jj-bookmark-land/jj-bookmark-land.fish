function __jj_bookmark_land_bookmarks
    jj bookmark list --ignore-working-copy -T 'if(!remote && present, name ++ "\n")' 2>/dev/null
end

function __jj_bookmark_land_needs_tip
    set -l tokens (commandline -opc)
    argparse --ignore-unknown 'into=' forget dry-run -- $tokens[2..] 2>/dev/null
    and test (count $argv) -eq 0
end

complete -c jj-bookmark-land -f
complete -c jj-bookmark-land -s h -l help -d 'Show help'
complete -c jj-bookmark-land -l into -r -f -d 'Destination bookmark' -a '(__jj_bookmark_land_bookmarks)'
complete -c jj-bookmark-land -l forget -d 'Forget landed bookmarks'
complete -c jj-bookmark-land -l dry-run -d 'Show the landing plan'
complete -c jj-bookmark-land -n __jj_bookmark_land_needs_tip -a '(__jj_bookmark_land_bookmarks)' -d 'Stack-tip bookmark'
