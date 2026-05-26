# Import PR

Import unresolved GitHub PR review comments as one or more new review phase files.

## References

- `references/contracts.md` — § Load Current Objective for the load/nudge gate, and § Invariants.
- `references/templates.md` — § Compute phase-file inputs for the sequence number (`NN`); the
  PR-review-specific phase-number, review-number (`M`), filename, and templates are in Contracts
  below.
- `references/phases.md` — Phase Index format and "never renumber" rule for the index entries.

## Steps

1. Get the branch name.

   ```bash
   jj-bookmark-current
   ```

2. Fetch unresolved PR comments.

   ```bash
   gh-pr-comments
   ```

   Returns a JSON array with: `databaseId`, `commentId`, `threadId`, `prNumber`, `prUrl`, `author`,
   `body`, `path`, `line`, `diffHunk`, `url`, `createdAt`, `isResolved`, `isOutdated`.

   If no unresolved comments, stop with: `No unresolved comments found`.

3. Load the current objective per `references/contracts.md` § Load Current Objective. Stop with this
   nudge if no valid objective is active:

   ```text
   No active objective. Want me to load or create one?
   ```

4. Compute phase-file inputs. Derive `NN` (the sequence number) per `references/templates.md` §
   Compute phase-file inputs, plus the two PR-review-specific values per § Phase Numbering below:
   the phase number `P` and the review number `M`.

5. Group comments by independence.
   - Classify comments into groups where each group addresses one cohesive concern.
   - Comments are interdependent when fixing one requires or affects the fix for another (e.g., same
     function, same abstraction, related API surface).
   - Comments are independent when they address unrelated concerns that could land in separate
     commits (e.g., naming fix in module A vs. error handling in module B).
   - Each independent group becomes its own phase — do not bundle unrelated feedback into one phase.
   - If all comments are interdependent, one phase is correct.
   - When multiple groups exist, give each a short slug summarizing its concern (e.g.,
     "error-handling", "naming-cleanup") — used in the phase title to differentiate.

6. Create phase file(s) — one per independent group — per § Phase File below. When creating multiple
   phases, increment both `P` and `NN` for each subsequent group (e.g., first group gets P=3 NN=05,
   second gets P=4 NN=06); filenames stay distinct via the differing `P`/`NN` prefixes, not via a
   slug.

7. Register each phase with a linked index entry in `00-main.md` per § Index Entry below — one per
   phase created.

8. Report.
   - PR number and URL.
   - Comment count imported.
   - Phase count and numbers created (note if comments were split across multiple phases).

## Contracts

### Phase Numbering

Computed via `references/templates.md` § Compute phase-file inputs for `NN`, with two
PR-review-specific values:

- Phase number `P`: highest phase number in the `## Phases` index in `00-main.md`; next `P` =
  highest + 1.
- Review number `M`: search existing phases for the `PR Review N` pattern; next `M` = highest + 1
  (start at 1 if none).
- Filename is `NN-phase-P-pr-review-M.md` (not the base `NN-phase-P.md`).

### Phase File

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

### Index Entry

Add a linked entry to `## Phases` in `00-main.md` per `references/phases.md` Phase Index — never
renumber existing phases. One entry per phase created:

```markdown
P. [ ] [PR Review M](./NN-phase-P-pr-review-M.md)
P. [ ] [PR Review M — <slug>](./NN-phase-P-pr-review-M.md)
```

Use the plain link text for single-group imports, the slug link text when multiple groups exist; the
filename is the same either way.

### Invariants

- Each import creates one or more phase files depending on comment independence; multiple groups
  accumulate as separate phases with incrementing `P`/`NN`/`M`.
- Only imports unresolved comments (`isResolved == false`).
- Preserve verbatim: the `No unresolved comments found` stop string, the no-objective nudge, the
  `gh-pr-comments` and `jj-bookmark-current` invocations and the comment JSON field list, the
  independence-grouping rules, the `NN-phase-P-pr-review-M.md` filename, the
  `## Phase P: PR Review M [— <slug>]` phase template (including the collapsible-diff format and the
  per-comment line format carrying author, body, and `[thread:<threadId>]`), the two index-entry
  link-text forms, and the report fields.
