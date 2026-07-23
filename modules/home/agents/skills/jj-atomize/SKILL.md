---
name: jj-atomize
description: >-
  Shapes unpublished jj history into coherent, fully described revisions. Use before describing or
  finalizing revisions, squashing or folding review fixes, splitting revisions, or reordering
  revisions in a stack, including changes involving only one revision; not for read-only inspection,
  ordinary edits, `jj new`, or bookmark management.
argument-hint: "[intent and optional revision set]"
---

Shape unpublished jj history by splitting, squashing, reordering, or describing revisions into the
fewest coherent, fully described revisions needed for review, rollback, and a cohesive story.

## Arguments

```
$ARGUMENTS
```

The request may be natural language. Infer three intents before acting:

- Target set: default to the task-owned bookmark ending at `@`, from its confirmed parent bookmark
  through its tip. Use an explicit jj revset, revision id, or range only when the request clearly
  names one. If no task-owned lower boundary can be established, stop and ask rather than absorbing
  other unpublished ancestry. Do not include the base or a published revision in the mutable set.
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

1. **Verify revision set** exists and contains changes (fail if empty).

   Inspect the revisions in topological order, their parent relationships, bookmarks, affected
   descendants, and publication and ownership status. Stop for approval when the base, destination,
   ownership, or rewrite boundary is ambiguous. Never rewrite published revisions without explicit
   approval. Before the first mutation, record the immutable base and the target tip's full commit
   ID for final aggregate-diff verification:

   ```bash
   old_tip="$(jj log -r <target> --no-graph -T 'commit_id')"
   ```

2. **Analyze changes and existing boundaries**:
   - Get the ordered revision graph and full descriptions with `jj log`.
   - Get each revision's full diff and `--stat` summary.
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

   - Identify dependencies between changes, including references to symbols, files, configuration,
     migrations, and behavior introduced elsewhere in the target set.

3. **Group, transform, and order**:
   - Start from the complete effective diff of the target set. Existing revision boundaries and
     order are evidence, not constraints.
   - Treat a candidate as coherent when one revision description can explain the change as a single
     reviewable concern without unrelated "and" clauses.
   - Keep code, tests, docs, configuration, and caller updates together when they support the same
     concern.
   - Split a revision when it contains independent concerns that are clearer, safer, or more
     reversible separately.
   - Squash adjacent or related revisions when they are partial steps of one concern, including
     fixups, tests, docs, or configuration that only make the same change complete.
   - Reorder revisions when the current order obscures the story or places a consumer before its
     dependency. Preserve dependency correctness; narrative preference never overrides it.
   - Describe only when boundaries and order are already coherent.
   - Do not split just because files differ by type, directory, conventional-commit type, or
     implementation layer.
   - Use the fewest coherent revisions. Build a dependency graph for every proposed revision (if B
     uses what A introduces, A comes first).
   - **Validate feasibility**:
     - If any file appears in multiple proposed revisions, it requires a hunk-level split.
     - Do not invoke an interactive VCS command. Merge affected revisions and note: "Grouped [X] and
       [Y] - splitting within [file] requires manual hunk selection" unless single-revision intent
       requires stopping instead.
   - Order the resulting stack:
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
   ## Atomic Stack: N revisions

   ### 1. type(scope): description

   Status quo or problem, then change in response.

   - file.ext (+X -Y): what changed

   ### 2. type(scope): description

   Status quo or problem, then change in response.

   - file.ext (+X -Y): what changed

   **Ordering**: [why this order]
   **Transformations**: [splits, squashes, reorders, and description-only updates]
   ```

5. **Iterate** based on feedback until confirmed. If inferred execution intent is not authorized,
   stop after the proposal.

6. **Execute** the accepted transformation plan:
   - Compose each full revision description (subject + body + footer) per the rules above
   - Format each agent-authored description with `commit-message-format`, assign the result, and
     validate that exact variable with `commit-message-check` before every `jj describe`,
     `jj split`, or `jj squash --message` write. If validation fails, revise the description and
     rerun the formatter and checker before writing. Do not format an exact user-supplied message.
   - Assign multi-line revision descriptions to a shell variable and pass the quoted variable to
     `-m`:

     ```bash
     desc='type(scope): description

     Status quo or problem, then change in response.'
     desc="$(printf '%s\n' "$desc" | commit-message-format)"
     printf '%s\n' "$desc" | commit-message-check
     jj describe -r <target> -m "$desc"
     ```

   - Apply structural changes before final descriptions. Split mixed revisions, squash fragments of
     the same concern, then reorder the resulting revisions into dependency order. Use
     non-interactive commands only.
   - For one coherent revision: run `jj describe -r <target> -m "$desc"`.
   - When using `jj squash`, always pass either `--use-destination-message` or `--message "$desc"`.
     Never squash without one of these options when both source and destination may have
     descriptions because jj will open an editor to combine them. Use `--use-destination-message`
     only when the destination already has the complete final description and discarding the source
     description is intentional. Also pass explicit `--from <source> --into <destination>`
     revisions; never rely on the implicit `@` source and parent destination.
   - For multiple coherent revisions, split every proposed revision except the final remainder in
     dependency order:

     ```bash
     desc="$(printf '%s\n' "$desc" | commit-message-format)"
     printf '%s\n' "$desc" | commit-message-check
     jj split -r <target> -m "$desc" file1 file2
     ```

   - After each split, track the selected revision, the remaining revision, and the target's rebased
     descendants. Use the remaining revision as the next target.
   - For reordering within a linear stack, use `jj rebase --revision <revision>` with an explicit
     `--insert-after <revision>` or `--insert-before <revision>` placement. Do not use `--source`,
     which also moves descendants, or `--onto`, which may create siblings instead of inserting the
     revision. Inspect the graph before and after every rebase and recompute rewritten revision IDs.
   - Do not reorder a revision across a dependency, outside the accepted target set, or across a
     merge boundary unless the proposal explicitly addresses the resulting graph and conflict risk.
   - Validate the final proposed description and apply it to the final remainder with
     `jj describe -r <remainder> -m "$desc"`. `jj split -m` describes only the selected changes;
     never leave the remainder with the original aggregate description or no description.
   - Resolve the final tip's full commit ID and compare its tree directly with the original tip:

     ```bash
     new_tip="$(jj log -r <final-target> --no-graph -T 'commit_id')"
     tree_diff="$(jj diff --from "$old_tip" --to "$new_tip" --summary)" || exit 1
     test -z "$tree_diff"
     ```

     Treat output or a nonzero result as a tree-changing transformation. Resolve or report
     conflicts; never present a conflicted or tree-changing stack as finalized.

   - Show the resulting graph, stable change IDs, commit IDs, and full descriptions with:

     ```bash
     jj log -r '<result-set>' --no-pager \
       --template 'change_id.short() ++ " " ++ commit_id.short() ++ "\n" ++ description ++ "\n\n"'
     ```

   - If the original target set ended at `@`, run `jj new` after finalizing the stack to create a
     fresh working copy. Do not leave finalized work active for subsequent edits.

7. **Report results**:
   - Report the exact revision IDs, order, and transformations produced.
   - State any descendants rebased by execution.
   - State that the aggregate diff was preserved and whether conflicts occurred.
