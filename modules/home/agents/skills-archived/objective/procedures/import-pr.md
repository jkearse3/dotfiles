# Import PR

Import unresolved GitHub PR review comments as one or more new review phase
files.

## References

- `references/current-objective.md` — § Load Current Objective for the
  load/nudge gate.
- `references/workflow-invariants.md` — § Invariants for caller-token
  preservation.
- `references/pr-review-import.md` — § PR Review Import Conventions for
  caller-visible import conventions.
- `references/phase-file-inputs.md` — § Compute Phase-File Inputs for the
  sequence number (`NN`).
- `references/phase-index.md` — Phase Index format and "never renumber" rule for
  the index entries.
- `references/phase-task-boundary.md` — § Phase Size for comment grouping.

## Steps

1. Get the branch name.

   ```bash
   jj-bookmark-current
   ```

2. Fetch unresolved PR comments.

   ```bash
   gh-pr-comments
   ```

   Returns a JSON array with: `databaseId`, `commentId`, `threadId`, `prNumber`,
   `prUrl`, `author`, `body`, `path`, `line`, `diffHunk`, `url`, `createdAt`,
   `isResolved`, `isOutdated`.

   If no unresolved comments, stop with: `No unresolved comments found`.

3. Load the current objective per `references/current-objective.md` § Load
   Current Objective, including its no-objective nudge.

4. Compute phase-file inputs. Derive `NN` (the sequence number) per
   `references/phase-file-inputs.md` § Compute Phase-File Inputs, plus the
   PR-review-specific values per `references/pr-review-import.md` § PR Review
   Import Conventions: the phase number `P` and the review number `M`.

5. Group comments by independence.
   - Classify comments into groups where each group addresses one cohesive
     concern.
   - Comments are interdependent when fixing one requires or affects the fix for
     another (e.g., same function, same abstraction, related API surface).
   - Comments are independent when they address unrelated concerns that could
     land in separate commits (e.g., naming fix in module A vs. error handling
     in module B).
   - Apply `references/phase-task-boundary.md` § Phase Size when deciding
     whether comments are separate enough to split or coupled enough to keep
     together.
   - Each independent group becomes its own phase — do not bundle unrelated
     feedback into one phase.
   - If all comments are interdependent, one phase is correct.
   - When multiple groups exist, give each a short slug summarizing its concern
     (e.g., "error-handling", "naming-cleanup") — used in the phase title to
     differentiate.

6. Create phase file(s) — one per independent group — per
   `references/pr-review-import.md` § PR Review Import Conventions. When
   creating multiple phases, increment `P`, `NN`, and `M` for each subsequent
   group (e.g., first group gets P=3 NN=05 M=1, second gets P=4 NN=06 M=2);
   filenames stay distinct via the differing `P`/`NN`/`M` prefixes, not via a
   slug.

7. Register each phase with a linked index entry in `00-main.md` per
   `references/pr-review-import.md` § PR Review Import Conventions — one per
   phase created.

8. Report.
   - PR number and URL.
   - Comment count imported.
   - Phase count and numbers created (note if comments were split across
     multiple phases).

## Contracts

### Invariants

- Only imports unresolved comments (`isResolved == false`).
- Preserve branch detection, `gh-pr-comments`, unresolved-comment filtering, the
  comment JSON field list, independence grouping, phase-file writes, index
  registration, and GitHub metadata handling.
