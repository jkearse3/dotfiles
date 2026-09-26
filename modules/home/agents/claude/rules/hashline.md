# File Editing

When the `mcp__hashline__*` tools are available, use them for existing text
files, even where other guidance prefers the shell: view with
`mcp__hashline__read` (with `offset` and `limit`) or `mcp__hashline__grep`
rather than Read, `cat`, `sed -n`, `head`, `tail`, or `grep -n`, and edit with
their edit tools rather than Edit, `sed -i`, `perl -i`, or heredoc or script
rewrites. Use Write only for new files or whole-file rewrites.
