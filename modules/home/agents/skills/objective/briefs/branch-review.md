# Branch Review Brief

Autonomous review pipeline over current branch changes: run an objective-context code review and
create cleanup phases for actionable findings.

## References

- `references/contracts.md` — § Invariants for the subagent write boundary and caller-token
  preservation.
- `references/branch-review.md` — § Autonomous Branch Review Conventions for the report fields,
  review phase numbering, review filename, phase-file shape, and index-entry shape.
- `references/phases.md` — Phase Index format and "never renumber" rule for the index entry written
  in Step 7.
- `references/templates.md` — New Phase template, § Phase Task Boundary, and § Compute phase-file
  inputs for `P`/`NN` and the index-entry registration.

## Write Permissions

- Write phase files at computed paths (create review phase files per `references/branch-review.md` §
  Autonomous Branch Review Conventions)
- Modify entries in `## Phases` in `00-main.md` (register new phase index entries; never renumber
  existing phases)

## Steps

1. Load objective context. Read `.objectives/_current/00-main.md`, including Context, Research,
   Acceptance Criteria, Approach, Phases, and Summary when present.

2. Load branch context. Run `jj diff --from "$(jj-bookmark-previous)" --stat` for the list of
   changed files with line counts. This defines the review scope.

3. Run objective-context code review. Invoke the `code-review` skill via the Skill tool with
   `branch` as the argument. Include the loaded objective context and branch scope in the review
   prompt so findings can account for objective intent, ACs, completed phases, and pre-PR drift.
   Collect structured findings.

4. Filter concerns. Keep actionable findings that apply to the branch review scope and should become
   objective cleanup work. Drop findings that are non-actionable, duplicates of existing open phase
   issues, or outside the current branch scope.

5. Early exit. If zero actionable findings remain: report "No concerns found" and stop cleanly.

6. Group into phases. Cluster concerns into coherent phases. Each phase is a single commit of
   related changes. Grouping criteria include same module/area, same type of concern (e.g., all
   naming fixes, all error handling), or logical dependency (fix X before Y). If only one coherent
   group, create a single phase.

7. Write phases. For each group, create a phase file whose tasks satisfy `references/templates.md` §
   Phase Task Boundary, and register it in `00-main.md` per `references/templates.md` New Phase
   template and § Compute phase-file inputs, with the review-specific conventions in
   `references/branch-review.md` § Autonomous Branch Review Conventions. Focus the first created
   phase (`*` in index) if no phase is currently focused.

## Contracts

### Invariants

- Dispatched as a subagent for autonomous execution; the orchestrator owns only dispatch and the
  user-facing summary.
- Preserve verbatim: the no-objective nudge, the `No concerns found` early-exit string, the
  `NN-phase-P-review-M.md` filename, and the phase-file and index-entry templates in
  `references/branch-review.md` § Autonomous Branch Review Conventions.
- The pipeline must not edit source files. Writes are limited to objective state: review phase files
  and the `## Phases` index in `00-main.md`.
- Multiple review sessions accumulate — each creates new phases with incrementing review numbers.
- The inner loop (review step within `phase-iterate`) is unchanged — it keeps its structured
  findings-to-issues pipeline for working-copy scope.
