# PR Review Import

Caller-visible conventions for importing unresolved GitHub PR review comments.

## PR Review Import Conventions

PR review imports use these caller-visible conventions.

Report fields:

- PR number and URL.
- Comment count imported.
- Phase count and numbers created, noting when comments were split across
  multiple phases.

Phase numbering and file naming use `references/phase-file-inputs.md` § Compute
Phase-File Inputs for `NN`, with three PR-review-specific values:

- Phase number `P`: highest phase number in the `## Phases` index in
  `00-main.md`; next `P` = highest + 1.
- Review number `M`: search existing phases for the `PR Review N` pattern; next
  `M` = highest + 1 (start at 1 if none).
- Filename is `NN-phase-P-pr-review-M.md` (not the base `NN-phase-P.md`).

Each import creates one or more phase files depending on comment independence.
Multiple groups accumulate as separate phases with incrementing `P`, `NN`, and
`M`.

Write `NN-phase-P-pr-review-M.md` with this content:

````markdown
## Phase P: PR Review M [— <slug>]

### Context

Address unresolved review feedback from PR #<prNumber> (<prUrl>).

### Approach

N comments from M reviewers.

#### path/file.go

- **L42** (@author): Comment body [thread:<threadId>]
  <details>
  <summary>Diff</summary>

  ```diff
  <diffHunk content>
  ```
  </details>

### Tasks

### Issues
````

Formatting rules:

- Group by file path (`#### <path>` headers under Approach).
- Format: `**L<line>** (@author): <body> [thread:<threadId>]`.
- Multi-line comments: first line or summary.
- Include `threadId` for reply operations.
- Diff context in collapsible details.

Add a linked entry to `## Phases` in `00-main.md` per
`references/phase-index.md` Phase Index — never renumber existing phases. One
entry is added per phase created:

```markdown
P. [ ] [PR Review M](./NN-phase-P-pr-review-M.md)
P. [ ] [PR Review M — <slug>](./NN-phase-P-pr-review-M.md)
```

Use the plain link text for single-group imports and the slug link text when
multiple groups exist; the filename is the same either way.

Preserve verbatim: the `No unresolved comments found` stop string, the
`gh-pr-comments` and `jj-bookmark-current` invocations and the comment JSON
field list, the independence-grouping rules, the `NN-phase-P-pr-review-M.md`
filename, the `## Phase P: PR Review M [— <slug>]` phase template (including the
collapsible-diff format and the per-comment line format carrying author, body,
and `[thread:<threadId>]`), the two index-entry link-text forms, and the report
fields.
