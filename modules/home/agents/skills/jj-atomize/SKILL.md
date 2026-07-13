---
name: jj-atomize
description: Organize unpublished jj changes into coherent, atomic, fully described revisions
argument-hint: "[intent and optional revision]"
---

Analyze unpublished jj changes and organize them into the fewest coherent, fully described revisions
needed for review, rollback, and history.

## Arguments

```
$ARGUMENTS
```

The request may be natural language. Infer three intents before acting:

- Target revision: default to `@`. Use an explicit jj revset or revision id only when the request
  clearly names one.
- Boundary intent: default to the fewest coherent revisions. Treat requests such as "single
  revision", "workflow close", "describe only", or "do not split" as single-revision intent.
- Execution intent: execute when the invocation explicitly requests mutation and identifies either
  current-task implementation authority or an explicit user request. An invocation that does not
  establish mutation authority is proposal-only.

Conservative parsing wins over cleverness: when target, boundary, or execution intent is ambiguous,
state the inferred intent in the proposal and wait for confirmation before running any `jj` command
that mutates history or descriptions.

Callers may provide explanatory context inline or through explicit file references they want
considered, such as lifecycle intent, constraints, decisions, acceptance criteria, evidence, or
verification notes. Treat that context as generic input for improving the revision-description
scope, subject, and body. The target diff remains authoritative for what changed; caller context can
explain why the change exists, but it must not invent changed content that is not supported by the
diff.

Revision descriptions must not expose agent, workflow, planning, or task-management internals.
Translate relevant caller context into codebase or domain rationale, and omit procedural mechanics
that do not belong in project history.

## Steps

1. **Verify revision** exists and has changes (fail if empty).

   Before proposing mutations, inspect whether the target or affected descendants are published or
   contain unrelated or user-authored work. Stop for approval when the destination, ownership, or
   rewrite boundary is ambiguous.

2. **Analyze changes**:
   - Get diff: `jj diff -r <revision>` (full) and `--stat` (summary)
   - For each file, identify:
     - What it introduces (new functions, types, exports)
     - What it uses (imports, references)
     - Type of change (conventional commits)
     - Scope (component/area affected)
   - For body content, identify:
     - Status quo or problem being solved
     - What the change does in response
     - Any breaking changes or related issues
     - Relevant caller context under the rules above

3. **Group and order**:
   - Start from one candidate revision containing the full target diff.
   - Treat a candidate as coherent when one revision description can explain the change as a single
     reviewable concern without unrelated "and" clauses.
   - Keep code, tests, docs, configuration, and caller updates together when they support the same
     concern.
   - Propose a split only when independent concerns would be clearer, safer, or more reversible as
     separate revisions for review, rollback, or history.
   - Do not split just because files differ by type, directory, conventional-commit type, or
     implementation layer.
   - If splitting is warranted, use the fewest coherent revisions. Build a dependency graph only for
     those proposed revisions (if B uses what A introduces, A comes first).
   - **Validate feasibility**:
     - If any file appears in multiple proposed revisions, it requires a hunk-level split.
     - Do not invoke an interactive VCS command. Merge affected revisions and note: "Grouped [X] and
       [Y] - splitting within [file] requires manual hunk selection" unless single-revision intent
       requires stopping instead.
   - Order proposed revisions:
     1. Dependencies first (hard constraint)
     2. Then by complexity: style < chore < docs < test < ci < build < refactor < perf < fix < feat
     3. Tie-breaker: fewer files first

4. **Present proposal**:

   Follow documented repository conventions when composing revision descriptions. Otherwise use the
   Conventional Commits type/scope taxonomy, a subject under 72 characters in imperative mood with
   no period, and a body that states the status quo before the change in response. Wrap body and
   footer lines at 72 characters; include breaking-change trailers and issue references when
   applicable.

   If coherent as one revision, or if single-revision intent was supplied and the target is
   coherent:

   ```
   ## Single Revision

   type(scope): description

   Status quo or problem, then change in response.

   **Files**: file1.ext, file2.ext
   **Reasoning**: [why coherent, why this message]
   ```

   If single-revision intent was supplied and the target is incoherent:

   ```
   ## Incoherent Target

   Cannot finalize as one coherent revision.

   **Independent concerns**: [list]
   **Reasoning**: [why one description would obscure review, rollback, or history]
   **Next decision needed**: narrow the target, allow splits, or move unrelated work out of scope.
   ```

   Stop after this finding. Do not split, describe, or otherwise mutate the target.

   If multiple coherent revisions are warranted and single-revision intent was not supplied:

   ```
   ## Split into N commits

   ### 1. type(scope): description

   Status quo or problem, then change in response.

   - file.ext (+X -Y): what changed

   ### 2. type(scope): description

   Status quo or problem, then change in response.

   - file.ext (+X -Y): what changed

   **Ordering**: [why this order]
   ```

5. **Iterate** based on feedback until confirmed. If inferred execution intent is not authorized,
   stop after the proposal.

6. **Execute** the accepted single-revision or multi-revision proposal:
   - Compose each full revision description (subject + body + footer) per the rules above
   - Format each agent-authored description with `commit-message-format`, assign the result, and
     validate that exact variable with `commit-message-check` before every `jj describe` or
     `jj split` write. If validation fails, revise the description and rerun the formatter and
     checker before writing. Do not format an exact user-supplied message.
   - Assign multi-line revision descriptions to a shell variable and pass the quoted variable to
     `-m`:

     ```bash
     desc='type(scope): description

     Status quo or problem, then change in response.'
     desc="$(printf '%s\n' "$desc" | commit-message-format)"
     printf '%s\n' "$desc" | commit-message-check
     jj describe -r <target> -m "$desc"
     ```

   - For one coherent revision: run `jj describe -r <target> -m "$desc"`.
   - For multiple coherent revisions, split every proposed revision except the final remainder in
     dependency order:

     ```bash
     desc="$(printf '%s\n' "$desc" | commit-message-format)"
     printf '%s\n' "$desc" | commit-message-check
     jj split -r <target> -m "$desc" file1 file2
     ```

   - After each split, track the selected revision, the remaining revision, and the target's rebased
     descendants. Use the remaining revision as the next target.
   - Validate the final proposed description and apply it to the final remainder with
     `jj describe -r <remainder> -m "$desc"`. `jj split -m` describes only the selected changes;
     never leave the remainder with the original aggregate description or no description.
   - Show every resulting revision and full description with
     `jj log -r '<first>::<last>' --no-pager`.
   - If the original target was `@`, run `jj new` after describing or splitting to create a fresh
     working copy. Do not leave finalized work active for subsequent edits.

7. **Report results**:
   - Report the exact revision IDs and order produced.
   - State any descendants rebased by execution.
