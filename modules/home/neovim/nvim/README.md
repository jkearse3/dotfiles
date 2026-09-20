# Neovim VCS inspection

## History and blame

- `<leader>glh`: repository history for the current file's repository (editor
  cwd for unnamed buffers). Enter opens a read-only commit patch; Ctrl-Y copies
  its SHA.
- `<leader>glf`: file history, following renames. Enter opens historical
  contents; Ctrl-S/Ctrl-V/Ctrl-T open them in a split, vertical split, or tab.
  Ctrl-D opens the full commit patch; Ctrl-Y copies the SHA.
- `<leader>gbf`: Gitsigns full-file blame; `<leader>gbl`: line blame.
- Existing `<leader>gd…` mappings retain the JJ inspection workflow.

The fzf-lua commit, file-commit, and reflog pickers use read-only action
allowlists, including when called directly with `:FzfLua`. Other Git pickers,
existing stage/reset mappings, and LazyGit are unchanged and can still mutate
repositories.

## Shareable links

`<leader>gy` copies a GitHub permalink for the current line, or the current
visual line range. `:CopyGitPermalink` also accepts an Ex line range.

Links use the full HEAD commit ID and URL-encoded repository-relative paths. The
helper requires a normal, named buffer whose contents and worktree file match
HEAD. Unsaved, staged, unstaged, untracked, and stale-buffer cases are rejected
rather than assigning misleading line numbers. Failure leaves the clipboard
unchanged.

Remote selection prefers the current branch's configured remote, then `origin`,
then a sole remote. Ambiguous remotes are rejected. HEAD must be reachable from
a local remote-tracking ref for that remote. This is an offline publication
check: it cannot detect stale tracking refs, remote deletion, or another
person's access permissions. Publish/fetch explicitly when necessary; the helper
never fetches.

Standard GitHub HTTPS and SSH URLs are supported. GitHub Enterprise hosts
require `vim.g.github_enterprise_urls = { "https://git.example.com" }`. SSH host
aliases and non-GitHub hosting providers are not inferred. Historical scratch
buffers are not permalink sources; select the corresponding working file
instead.

Fugitive commands (`:Git`, `:Gedit`, `:Gdiffsplit`, `:GBrowse`, etc.) and
Rhubarb's commit-message omnifunc are no longer installed.

See [tests/README.md](tests/README.md) for isolated regression-test commands.
