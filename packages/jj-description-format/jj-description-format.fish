function __jj_description_format_bookmarks
    jj bookmark list --ignore-working-copy -T 'if(!remote && present, name ++ "\n")' 2>/dev/null
end

complete -c jj-description-format -f
complete -c jj-description-format -s h -l help -d 'Show help'
complete -c jj-description-format -s r -l revision -r -f -d 'Target revision' -a '(__jj_description_format_bookmarks)'
complete -c jj-description-format -l dry-run -d 'Show the diff without writing'
complete -c jj-description-format -l subject-width -r -f -d 'Maximum subject width'
complete -c jj-description-format -l body-width -r -f -d 'Maximum body line width'
