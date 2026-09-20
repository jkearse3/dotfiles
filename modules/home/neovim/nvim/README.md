# Neovim VCS inspection

## History and blame

- `<leader>glh`: repository history for the current file's repository (editor
  cwd for unnamed buffers). Enter opens a read-only commit patch; Ctrl-Y copies
  its SHA.
- `<leader>glf`: file history, following renames. Enter opens historical
  contents; Ctrl-S/Ctrl-V/Ctrl-T open them in a split, vertical split, or tab.
  Ctrl-D opens the full commit patch; Ctrl-Y copies the SHA.
- `<leader>gbf`: Gitsigns full-file blame; `<leader>gbl`: line blame.
- JJ comparisons use the shared file overview described below.

The fzf-lua commit, file-commit, and reflog pickers use read-only action
allowlists, including when called directly with `:FzfLua`. Other Git pickers,
existing stage/reset mappings, and LazyGit are unchanged and can still mutate
repositories.

## JJ inspection

All complete JJ comparisons use one retained, read-only **file overview**.
Opening it loads metadata only: every file starts collapsed, including a focused
file. There is no mandatory file-scope picker.

| Key          | Inspect                                                                                            |
| ------------ | -------------------------------------------------------------------------------------------------- |
| `<leader>jl` | Configured JJ revision history; Enter reviews a revision against its parents.                      |
| `<leader>jb` | Local bookmark range: nearest strictly older first-parent bookmark → selected bookmark.            |
| `<leader>jf` | Rename-aware file history; Enter reviews the whole revision, focusing its historical filename.     |
| `<leader>ja` | Recorded origin of the current line; focus its historical file header in the responsible revision. |
| `<leader>jr` | Resume the retained overview without refreshing or loading patches.                                |
| `<leader>jx` | Cancel pending source lookup and outstanding review requests, including from a source-file buffer. |

The former `gdb` and `gdl` routes are now `jb` and `ja`. `gds` is removed: use
`jr` to return to review and buffer-local `f` to find a file. `gdr` and
standalone `je` are also absent. Git mappings remain separate; JJ failures never
silently switch comparison semantics to Git.

Revision and file-history pickers show metadata, not patches. Both list at most
200 revisions; Enter opens the shared overview, Ctrl-E opens previous drafts of
the selected change, and Ctrl-Y copies its change ID. Unnamed and non-file
buffers are rejected for file/line inspection.

`jf` traces the recorded file backward through single-parent commits and
detected renames, including rename-plus-edit and repeated renames. Each row and
preview shows its historical filename; Enter selects that file's collapsed
header. Lookup is asynchronous, uses only metadata, and pins one operation.
`<leader>jx` cancels it; switching buffers discards late results. Unsaved
contents are not snapshotted; the path must exist in recorded `@`.

Rename detection is **inferred**, not definitive file identity. The header
always explains where tracing ended. Additions (including copies or undetected
renames), merges, and competing removed/renamed source paths stop traversal. A
delete/recreate does not join separate file lifetimes. Even unrelated
simultaneous deletions can make a rename too uncertain to follow. No merge
parent is silently selected.

Lookup skips unchanged commits, inspects at most 500 candidate commits, and
returns at most 200 matching revisions. A 30-second traversal budget is checked
between revisions; each individual request also has the existing 30-second
timeout and 2 MiB metadata cap. Budget-limited results are explicitly labeled
partial. Use Git `glf` if you need its alternative rename/history behavior. This
does not change `ja`'s annotation semantics or its existing 1 MiB analysis-patch
limit.

Bookmark ranges retain their existing first-parent policy—not a guessed default
branch or merge base. Missing ancestor bookmarks and ambiguous/conflicted
targets are errors. Multiple normal bookmark names at the same base are shown
together. The overview names the comparison and shows exact immutable
base/target IDs. Source resolution pins one JJ operation across its requests.

`ja` verifies disk and loaded buffer text against a pinned recorded `@` before
attributing a line. It follows historical renames and line shifts, refuses
ambiguous or copied/deleted mappings, and reports the historical path and line.
The file header is selected without expanding it: expand and page to inspect the
reported line. Saved-but-unrecorded edits, unsaved edits, and stale buffers are
refused.

### Within the overview

- **Enter:** expand/collapse a file. Only expansion loads its displayed patch.
- **`]f` / `[f`**, **`f`:** navigate/find file headers without loading patches.
- **`]c` / `[c`:** navigate hunks in displayed pages only.
- **`]p` / `[p`:** next/previous bounded patch page for the current file.
- **`gf`:** map a surviving source line from the comparison's target to recorded
  working-copy contents. Deleted lines have no target; unsafe disk/buffer
  mismatches are refused rather than jumping to misleading offsets.
- **`x`:** cancel pending source lookup and review requests.
- **`R`:** resolve the latest change or bookmark range, invalidate caches on
  success, and reload collapsed metadata. A failed source resolution retains the
  pinned view and completed caches. Historical drafts instead reload their exact
  commit.

Reviews stay pinned until explicit refresh. The source-line gutter, syntax
highlighting, quickfix index, paging and navigation are shared across entry
points. Search and hunk navigation cover displayed pages, not unloaded text.

Each page contains at most 400 patch lines / 128 KiB. File generation is
asynchronous and cancellable, spooling privately to disk; pages render after
generation finishes. Collapse retains the cache. At most eight files are
expanded and sixteen file caches retained, with least-recently-used
collapse/eviction.

Each request times out after 30 seconds. File spools are capped at 32 MiB;
metadata at 2 MiB / 10,000 files; individual patch lines at 128 KiB. Line-origin
resolution analyzes two complete comparison patches to disambiguate renames,
with a **1 MiB limit on each analysis patch**; it never silently truncates them.
File verification and working-copy jump mapping also have 1 MiB limits. If line
inspection exceeds these limits, use revision/bookmark review or external tools
instead. Failed patch generation never displays partial output. Replacement,
deletion, cancellation and editor exit clean up owned temporary files.

### Previous drafts

Select a change in `jl` or `jf`, then **Ctrl-E**. This is draft history, not
commit ancestry: the selected revision and up to 199 predecessors are shown with
recording timestamps, exact commit IDs and descriptions.

- **Preview / Enter:** labeled changes from the draft's actual predecessor(s),
  with unrelated rebase-parent changes excluded by `jj evolog`. An initial draft
  has no earlier comparison. This interdiff remains a distinct read-only patch
  view.
- **Ctrl-D:** open the shared collapsed overview for that draft against its
  parents. Its refresh remains pinned to the exact draft, not the latest change
  version.
- **Ctrl-Y:** copy the stable change ID.

Inspection does not restore drafts, snapshot files, import Git refs, reconcile
divergent operation heads, or advance the operation log. Record edits and
resolve divergence through your normal JJ workflow first.

### Git-only alternatives

When JJ is unavailable or the repository is Git-only, use the existing explicit
Git routes: `glh` for repository history, `glf` for rename-following file
history, `gbl` for full line blame, and `gbf` for full-file blame. In the
Gitsigns blame buffer, `s` inspects the responsible commit. LazyGit (`gg`) and
existing mutation and gutter mappings are unchanged.

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
