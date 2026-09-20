# Neovim VCS inspection

## History and blame

- `<leader>glh`: repository history for the current file's repository (editor
  cwd for unnamed buffers). Enter opens a read-only commit patch; Ctrl-Y copies
  its SHA.
- `<leader>glf`: file history, following renames. Enter opens historical
  contents; Ctrl-S/Ctrl-V/Ctrl-T open them in a split, vertical split, or tab.
  Ctrl-D opens the full commit patch; Ctrl-Y copies the SHA.
- `<leader>gbf`: Gitsigns full-file blame; `<leader>gbl`: line blame.
- Existing `<leader>gdb`, `<leader>gdl`, and `<leader>gds` retain specialized JJ
  review.

The fzf-lua commit, file-commit, and reflog pickers use read-only action
allowlists, including when called directly with `:FzfLua`. Other Git pickers,
existing stage/reset mappings, and LazyGit are unchanged and can still mutate
repositories.

## JJ history

`<leader>jl` opens JJ's configured default log selection (normally local mutable
changes plus context). The picker lists up to 200 revisions in topology order,
with change IDs, commit IDs, bookmarks and descriptions. The picker preview is
metadata only. Enter opens the selected revision's retained **file overview**,
with no patches loaded. `<leader>gdr` has been removed in favor of this one
entry point. Ctrl-Y copies the change ID; Ctrl-E opens previous drafts of the
selected change.

Within the overview:

- **Enter** expands/collapses the current file. Only expansion requests its
  patch.
- **`]f` / `[f`** move between all file headers; **`f`** finds a file. Neither
  loads it.
- **`]c` / `[c`** navigate hunks in currently displayed pages only.
- **`]p` / `[p`** replace the current file's page with the next/previous page.
- **`gf`** maps a surviving source line to the working copy using the existing
  JJ review navigation. Deleted lines have no working-copy target. Disk and
  buffer contents must match the recorded working snapshot; unsnapshotted edits
  and stale buffers are refused rather than jumping to misleading line numbers.
- **`x`** cancels outstanding requests. **`R`** resolves the latest version of
  the change, clears cached patches, and reloads the collapsed overview.

The existing syntax-aware review renderer, line-number gutter and quickfix index
are reused. Search and hunk navigation cover displayed pages, not unloaded text.
The review stays pinned until explicit refresh.

Every file follows the same bounded-page flow: up to 400 patch lines / 128 KiB
per page. JJ generates an explicitly requested file patch asynchronously into a
private temporary disk cache, rather than collecting the entire patch in Lua.
Generation is cancellable; pages render after generation finishes. Collapsing
retains the cache. At most eight files are expanded, and sixteen file caches are
retained; least-recently-used entries collapse/evict as needed.

Requests time out after 30 seconds. File caches are limited to 32 MiB each; the
overview is limited to 2 MiB / 10,000 files. A single patch line exceeding 128
KiB is refused explicitly. Working-copy jumps require mapping diffs and
destination files of at most 1 MiB each. Failures never display a partial
generated patch. Refresh, replacement, deletion and editor exit clean up caches
and cancel outstanding work.

**Previous drafts of this change** is contextual: select a change in `jl`, then
press **Ctrl-E**. There is no standalone `<leader>je` mapping. The view includes
the selected revision and its earlier recorded drafts, capped at 200 entries.
Rows show recording timestamps (with timezone), exact commit IDs, and
descriptions; the selected revision is labeled. This is draft history, not
commit ancestry.

- **Preview / Enter:** changes from the selected draft's actual predecessor(s)
  to that draft. The comparison names both sides; `jj evolog` excludes unrelated
  parent changes introduced by rebasing. An initial draft is labeled as having
  no earlier recorded draft.
- **Ctrl-D:** that draft's complete patch against its parents, explicitly
  labeled as a different comparison.
- **Ctrl-Y:** copy the stable change ID.

Description-only edits and rebases can produce drafts without source-code
changes. Inspection never restores a draft or records unsaved edits.

`<leader>jf` lists up to 200 revisions affecting the current file in `@`'s
ancestry. Enter inspects only that path's patch; Ctrl-E opens previous drafts of
the whole selected change; Ctrl-Y copies its change ID. Paths are literal,
including fileset metacharacters. This is path-based history, not
rename-following history; use `<leader>glf` to follow renames. Unnamed and
non-file buffers are rejected.

These pickers resolve the current file's repository, falling back to editor cwd
for non-file buffers. Commands use `--at-operation=@ --ignore-working-copy`:
they do not snapshot disk edits, import Git refs, or advance JJ's operation log.
They show the last recorded snapshot, not unsaved or subsequently changed files.
Record changes through your normal JJ workflow before inspecting them here.
Existing Git history, `jf`, and the specialized `gdb`/`gdl`/`gds` mappings are
otherwise unchanged; lazy file expansion applies to the `jl` revision overview.

Divergent operation heads are reported as an error, not automatically
reconciled. Resolve them explicitly through your normal JJ workflow before
reopening history.

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
