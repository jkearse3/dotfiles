# Import PR

Import unresolved GitHub PR review comments as a new review phase file.

Read these format references before executing this procedure:

- `${CLAUDE_SKILL_DIR}/references/phases.md`
- `${CLAUDE_SKILL_DIR}/references/templates.md`

## Steps

1. **Get branch name**:

   ```bash
   jj-bookmark-current
   ```

2. **Fetch unresolved PR comments**:

   ```bash
   gh-pr-comments
   ```

   Returns JSON array with: `databaseId`, `commentId`, `threadId`, `prNumber`, `prUrl`, `author`,
   `body`, `path`, `line`, `diffHunk`, `url`, `createdAt`, `isResolved`, `isOutdated`

   If no unresolved comments: "No unresolved comments found" → stop

3. **Load goal**: `.claude/_goals/_current/00-main.md`
   - If symlink broken: nudge — "No active goal. Want me to load or create one?"

4. **Determine phase number**:
   - Find highest phase number in `## Phases` index in `00-main.md`
   - Next phase = highest + 1

5. **Determine review number**:
   - Search existing phases for `PR Review N` pattern
   - Next review = highest + 1 (start at 1 if none)

6. **Determine sequence number**: Scan goal directory for highest `NN-` prefix + 1

7. **Group comments by independence**:
   - Classify comments into groups where each group addresses one cohesive concern
   - Comments are interdependent when fixing one requires or affects the fix for another (e.g., same
     function, same abstraction, related API surface)
   - Comments are independent when they address unrelated concerns that could land in separate
     commits (e.g., naming fix in module A vs. error handling in module B)
   - Each independent group becomes its own phase — do not bundle unrelated feedback into one phase
   - If all comments are interdependent, one phase is correct
   - When multiple groups exist, give each a short slug summarizing its concern (e.g.,
     "error-handling", "naming-cleanup") — used in the phase title to differentiate

8. **Create phase file(s)** — one per independent group.
   - Filename: `NN-phase-P-pr-review-M.md`
   - When creating multiple phases, increment both P and NN for each subsequent group (e.g., first
     group gets P=3 NN=05, second gets P=4 NN=06); filenames stay distinct via the differing
     `P`/`NN` prefixes, not via a slug

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
   - Group by file path (`#### <path>` headers under Approach)
   - Format: `**L<line>** (@author): <body> [thread:<threadId>]`
   - Multi-line comments: first line or summary
   - Include threadId for reply operations
   - Diff context in collapsible details

9. **Add linked index entry** to `## Phases` in `00-main.md` (one per phase created):

   ```markdown
   P. [ ] [PR Review M](./NN-phase-P-pr-review-M.md)
   P. [ ] [PR Review M — <slug>](./NN-phase-P-pr-review-M.md)
   ```

   Use the plain link text for single-group imports, the slug link text when multiple groups exist;
   the filename is the same either way.

10. **Report**:
    - PR number and URL
    - Comment count imported
    - Phase count and numbers created (note if comments were split across multiple phases)

## Notes

- Each import creates one or more phase files depending on comment independence
- Only imports unresolved comments (isResolved == false)
