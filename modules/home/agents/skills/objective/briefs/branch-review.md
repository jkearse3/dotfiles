# Branch Review Brief

Autonomous review pipeline over current branch changes: capture `REVIEW:` comments from code, run
code review, merge findings, and create cleanup phases.

## References

- `references/contracts.md` — § Invariants for the subagent write boundary and caller-token
  preservation.
- `references/branch-review.md` — § Autonomous Branch Review Conventions for the report fields,
  review phase numbering, review filename, phase-file shape, and index-entry shape.
- `references/phases.md` — Phase Index format and "never renumber" rule for the index entry written
  in Step 8.
- `references/templates.md` — New Phase template and § Compute phase-file inputs for `P`/`NN` and
  the index-entry registration.

## Write Permissions

- Write phase files at computed paths (create review phase files per `references/branch-review.md` §
  Autonomous Branch Review Conventions)
- Modify entries in `## Phases` in `00-main.md` (register new phase index entries; never renumber
  existing phases)

## Steps

1. Load branch context. Run `jj diff --from "$(jj-bookmark-previous)" --stat` for the list of
   changed files with line counts. This defines the review scope.

2. Capture REVIEW comments. Grep the entire repository for the multi-language REVIEW pattern:

   ```
   (//|#|--|/\*|\*|<!--)\s*REVIEW:\s*(.+)$
   ```

   This covers Go/JS/TS/Rust/C (`//`), Nix/Python/Shell/YAML (`#`), Lua/SQL (`--`), CSS (`/*`/`*`),
   HTML/XML (`<!--`). For each match record file path, line number, and description (capture group
   2, then trim trailing `\s*-->` or `\s*\*/` from HTML/XML/CSS closers).

   Multi-line comments: if a `REVIEW:` line is found, read forward until a line matching
   `(//|#|--|/\*|\*|<!--)\s*/REVIEW` is found. Concatenate all intermediate lines as the
   description; the `/REVIEW` terminator is part of the block.

   Scope tagging: cross-reference each captured comment's file path against the Step 1 branch diff
   stat. Tag each as `in-scope` (file is in the branch diff) or `out-of-scope` (file is not — a
   pre-existing concern the user noticed while working). If no matches, proceed with an empty list.

3. Remove REVIEW comments. For each captured comment, delete it from the source file — single-line:
   delete the `REVIEW:` line; multi-line: delete from the `REVIEW:` line through the `/REVIEW`
   terminator inclusive. Adjacent non-REVIEW comments must not be affected. This must happen before
   the code review so the reviewer sees clean code.

4. Run code review. Invoke the `code-review` skill via the Skill tool with `branch` as the argument.
   Collect structured findings.

5. Merge concerns. Combine human REVIEW comments and code-review findings into a single concern
   list. Each entry has file path, line number, description, source (`human` from REVIEW comments or
   `review` from code review), and scope (`in-scope` or `out-of-scope`; human comments only — code
   review findings are always in-scope). No dedup — keep both when overlapping; human and automated
   perspectives are both valuable.

6. Early exit. If zero concerns (no REVIEW comments captured AND code review returned no findings):
   report "No concerns found" and stop cleanly.

7. Group into phases. Separate concerns by scope first, then cluster within each scope.

   In-scope concerns: cluster into coherent phases. Each phase is a single commit of related
   changes. Grouping criteria — same module/area, same type of concern (e.g., all naming fixes, all
   error handling), or logical dependency (fix X before Y). If only one coherent group, create a
   single phase.

   Out-of-scope concerns: group into a separate phase named `Review M: Pre-existing concerns`. These
   are issues the user flagged in files outside the branch diff; they get their own phase so they
   don't mix with branch-specific cleanup. If none, skip this group.

8. Write phases. For each group, create a phase file and register it in `00-main.md` per
   `references/templates.md` New Phase template and § Compute phase-file inputs, with the
   review-specific conventions in `references/branch-review.md` § Autonomous Branch Review
   Conventions. Focus the first created phase (`*` in index) if no phase is currently focused.

## Contracts

### REVIEW Comment Convention

Single-line (no end marker needed):

```
# REVIEW: short concern about this code
```

Multi-line (explicit `/REVIEW` terminator):

```
# REVIEW: longer concern that needs
# multiple lines to explain the issue
# and suggest a direction
# /REVIEW
```

### Invariants

- Dispatched as a subagent for autonomous execution; the orchestrator owns only dispatch and the
  user-facing summary.
- Preserve verbatim: the no-objective nudge, the REVIEW regex and `/REVIEW` terminator pattern, the
  `No concerns found` early-exit string, the `Review M: Pre-existing concerns` phase name, the
  `NN-phase-P-review-M.md` filename, the phase-file and index-entry templates in
  `references/branch-review.md` § Autonomous Branch Review Conventions, the `human`/`review` source
  tags, and the `in-scope`/`out-of-scope` scope tags.
- REVIEW comment removal (Step 3) happens before code review — the reviewer sees clean code.
- Multiple review sessions accumulate — each creates new phases with incrementing review numbers.
- REVIEW comments in files outside the branch diff are captured as `out-of-scope` and grouped into a
  separate "Pre-existing concerns" phase.
- The inner loop (review step within `phase-iterate`) is unchanged — it keeps its structured
  findings-to-issues pipeline for working-copy scope.
