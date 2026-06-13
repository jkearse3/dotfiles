---
name: jj-atomize
description: Finalize jj revision descriptions and split only when review clarity requires it
argument-hint: "[intent and optional revision]"
---

Analyze a jj revision and either describe it as one coherent revision or propose the fewest coherent
revisions needed for review, rollback, and history.

## Arguments

```
$ARGUMENTS
```

The request may be natural language. Infer three intents before acting:

- Target revision: default to `@`. Use an explicit jj revset or revision id only when the request
  clearly names one.
- Boundary intent: default to the fewest coherent revisions. Treat requests such as "single
  revision", "workflow close", "describe only", or "do not split" as single-revision intent.
- Execution intent: default to propose-only when mutation intent is unclear. Mutate only when the
  user explicitly asks to apply, write, finalize, commit, describe, split, or otherwise execute.

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
     - Caller-provided rationale, constraints, evidence, or verification details that improve the
       description without contradicting the target diff

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
     - If any file appears in multiple proposed revisions, it requires hunk-level split.
     - Merge affected revisions and note: "Grouped [X] and [Y] - splitting within [file] requires
       interactive mode" unless single-revision intent requires stopping instead.
   - Order proposed revisions:
     1. Dependencies first (hard constraint)
     2. Then by complexity: style < chore < docs < test < ci < build < refactor < perf < fix < feat
     3. Tie-breaker: fewer files first

4. **Present proposal**:

   Follow the repo's version-control rules when composing revision descriptions — type/scope
   taxonomy, subject format (72 chars, imperative mood, no period), body (status quo first, then
   change; contextual mood; domain language; wrap at 72), footer (breaking change trailer, issue
   refs).

   Use caller-provided context to sharpen the revision scope, subject, and body only when it is
   relevant to the target diff. The diff remains the authority for changed content; do not include
   caller context that is unrelated to the changed files or unsupported by the diff. Do not mention
   agent actions, workflow phases, planning artifacts, task lists, or other task-management
   mechanics. Convert useful context into codebase or domain rationale instead.

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

5. **Iterate** based on feedback until confirmed. If execution intent was not explicit, stop after
   the proposal and ask for confirmation before mutating the target.

6. **Execute** using the single-revision or multi-commit pattern from the repo's version-control
   rules:
   - Compose each full revision description (subject + body + footer) per the rules above
   - Validate the exact description variable with `commit-message-check` before every `jj describe`
     or `jj split` write. If validation fails, revise the description and rerun the checker before
     writing.
   - Assign multi-line revision descriptions to a shell variable and pass the quoted variable to
     `-m`:

     ```bash
     desc='type(scope): description

     Status quo or problem, then change in response.'
     printf '%s\n' "$desc" | commit-message-check
     jj describe -r <target> -m "$desc"
     ```

   - For one coherent revision: run `jj describe -r <target> -m "$desc"`. Do not create a new
     revision.
   - For multiple coherent revisions: use the multi-commit splitting pattern:

     ```bash
     printf '%s\n' "$desc" | commit-message-check
     jj split -r <target> -m "$desc" file1 file2
     ```

   - Track `first_commit` and `target` through splits
   - Show result with `jj log -r '<first>::<last>'`
   - If original target was `@` and splitting created finalized revisions: run `jj new` to create a
     fresh working copy
