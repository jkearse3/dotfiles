# Phase Iterate

Orchestrate the inner loop: scope a phase if none is active, run the implement-verify loop inline,
then enrich AC status and commit.

## Arguments

- `--auto-commit`: Steps 6 and 8 return a structured `PHASE_INCOMPLETE` diagnostic on failure
  (blocked tasks, unresolved issues, or implement concerns) instead of stopping for user input, and
  Step 9 auto-commits and returns a structured `PHASE_COMPLETE` result instead of waiting for user
  review.

## References

- `references/current-objective.md` — Load Current Objective.
- `references/phase-iterate-results.md` — Phase Iterate Result Blocks.
- `references/reconciliation-routing.md` — Reconciliation Result Contract.
- `references/workflow-invariants.md` — approval-gate, continuation, and single-revision invariants.
- `references/auto-scope-dispatch.md` — Auto-scope Dispatch.
- `references/phase-index.md` — Phase Resolution (locate focused phase content).
- `references/phase-file-inputs.md` — Compute Phase-File Inputs and phase-index entry shape.
- `references/ac-markers.md` — AC marker and evidence semantics.

## Steps

Run in order. Do not improvise or skip steps. Announce each step number before executing it (e.g.,
"Step 4: Run Implement") to maintain orientation.

1. Load state. Read `.objectives/_current/00-main.md` fresh (never rely on prior context) per
   `references/current-objective.md` § Load Current Objective, including its no-objective nudge.
   - If no ACs in `## Acceptance Criteria`: nudge — "No acceptance criteria defined yet. Want me to
     run `/objective spec`?"

   Objective commit (one-time, before first phase): if no phases exist yet and objective files are
   tracked in version control (check with `jj st`), commit the objective to preserve the spec as a
   checkpoint independent of implementation. Compose the full revision description using the repo's
   version-control rules. If the working copy contains only objective files, commit them with
   `jj commit -m "$desc"`. If other files are also present, use
   `jj split -m "$desc" <objective-files>` to commit only the objective files.

2. Ensure focused phase. Find the focused phase (`*` in `## Phases`).
   - If a focused phase exists: go to Step 3.
   - If none: run `references/auto-scope-dispatch.md` § Dispatch with these procedure-specific
     results, using the default auto-accept Phase proposal handler:
     - No work remaining: report "Nothing to iterate." and stop.
     - Readiness issues: surface them and stop.
     - Phase proposal: auto-accept (no user approval), re-read `00-main.md` to pick up the new
       phase, and go to Step 3.

3. Announce scope. Locate the focused phase file per `references/phase-index.md` § Phase Resolution.
   Announce before executing:
   - Phase name and number.
   - Pending tasks (count and brief list).
   - Open issues (count).
   - Targeted ACs (from task references).

   If the focused phase contains `### Continuation`, read Status, Source, Route, Summary, Clear
   when, and any Payload before deciding where to resume. Treat Route as the primary resume
   instruction and do not rely on prior chat context. If Route names a step in this procedure,
   resume at that step after this announcement. If Route names another objective procedure, stop and
   report the continuation details so the caller can run the routed procedure without mutating the
   continuation.

4. Run implement. Dispatch an implementation subagent with prompt:

   ```text
   Read the bundled skill resource `briefs/phase-implement.md` and execute the instructions within it.

   State file: <absolute path to phase file>
   AC source: .objectives/_current/00-main.md
   ```

   Always dispatch — never skip based on task state. The subagent decides whether work remains (open
   issues need tasks even when existing tasks are complete). If the subagent returns concerns
   requiring user input, stop and surface them.

   Check for blockers before verify: read the phase file. If any task is `[!]` and no pending `[ ]`
   tasks remain, skip Step 5 and go directly to Step 6 (termination check). This prevents verify
   from returning "no changes" and halting the loop before blockers surface. Otherwise go to Step 5.

5. Run verify. Dispatch a verify subagent with prompt:

   ```text
   Read the bundled skill resource `briefs/phase-verify.md` and execute the instructions within it.

   State file: <absolute path to phase file>
   AC source: .objectives/_current/00-main.md
   ```

   Capture AC assessments. When verify returns AC validation results, parse them into a structured
   `ac_status` list of `{ac, status, evidence}` entries:

   | Verify section           | Status |
   | ------------------------ | ------ |
   | `### Validated`          | `[x]`  |
   | `### Needs Verification` | `[~]`  |
   | `### Regressions`        | `[!]`  |
   | `### Not Implemented`    | `[ ]`  |

   Store as the latest `ac_status` snapshot. Each subsequent AC-validation verify run replaces the
   previous snapshot (latest-verify-wins).

   Snapshot preservation on non-AC-validation returns: when verify returns a review-only summary
   (new issues found) or "No changes to verify.", preserve the existing `ac_status` snapshot
   unchanged — do not clear or overwrite it. Only AC-validation returns update the snapshot, so Step
   7a retains prior assessments when later iterations short-circuit before AC validation.

   Check verify result:
   - New issues (review-only summary with new issues): return to Step 4 (implement will create tasks
     for the new issues).
   - Summary contains the exact string `No changes to verify.` (contract with
     `briefs/phase-verify.md` Step 2 — do not change either without updating both): go to Step 6
     (termination check). Do not stop — state-file-only iterations still need completion handling.
   - AC validation completed:
     - Any `[~]` ACs not marked `(human)`: return to Step 4 (implement assesses testability).
     - All `[~]` are `(human)` or all ACs `[x]`: go to Step 6.

6. Check loop termination. Read the phase file. The loop is complete when ALL of:
   - All tasks are `[x]` (no pending `[ ]` tasks remain).
   - No open issues exist (no `[ ]` issues remain).
   - No tasks are blocked `[!]`.

   - If blocked tasks exist: stop and surface them — report which tasks are blocked and why; wait
     for user direction. With `--auto-commit`, return `PHASE_INCOMPLETE` per
     `references/phase-iterate-results.md` § Phase Iterate Result Blocks with reason `blocked_tasks`
     and blocker details.

   - If not complete (pending tasks or open issues remain but no blockers): return to Step 4 for
     another cycle.
   - If complete: go to Step 7.

7. Present summary and check phase termination. Summarize:
   - Tasks: total / completed / blocked (from phase file).
   - Issues: total open (by severity).
   - ACs: status changes, regressions (`[!]`), remaining `[~]` (with human/test distinction).
   - Phase: complete or not.

   Phase is complete when ALL of:
   - All phase tasks `[x]`.
   - All phase issues resolved.

   - If complete:
     - Keep the phase focused and incomplete in the index until explicit Step 8 approval/commit.
     - Collect targeted ACs from task references (`(ACN, satisfy)` / `(ACN, codify)` /
       `(ACN, enhance)`) for the summary.
     - Go to Step 8 (review and commit).
   - If `[~] (human)` ACs remain: stop the loop and present the ACs needing human verification. The
     phase can still be complete if tasks and issues are resolved — AC validation is an
     objective-level concern.
   - If not complete for other reasons:
     - Without `--auto-commit`: stop. User decides whether to run another cycle.
     - With `--auto-commit`: return `PHASE_INCOMPLETE` per `references/phase-iterate-results.md` §
       Phase Iterate Result Blocks using the matching reason and details.

8. Review and commit.

   Without `--auto-commit`: announce that the phase is ready for review and wait for user approval
   before committing.
   1. Announce: "Phase N complete. Review the diff and approve when ready." Do NOT print or display
      the diff — the user reviews it independently.
   2. Wait for the user, who either approves or requests tweaks.
   - If the user approves:
     1. Mark phase complete in index (`[x]`) and remove the focus marker (`*`).
     2. Read and follow `procedures/summarize.md` with `--auto` to ensure the summary reflects the
        final committed state.
     3. Compose the full revision description using the repo's version-control rules.
     4. Commit the phase with `jj commit -m "$desc"`.
     5. Note "Phase complete. Run `/objective phase-iterate` to scope and execute next phase."
   - If the user requests tweaks:
     1. Dispatch a reconciliation subagent with prompt:

        ```text
        Read the bundled skill resource `briefs/phase-reconcile.md` and execute the instructions within it.

        State file: <absolute path to phase file>
        AC source: .objectives/_current/00-main.md
        Review feedback:
        <verbatim user feedback>
        ```

     2. Route the reconciliation `### Top-Level Status` deterministically per
        `references/reconciliation-routing.md` § Reconciliation Result Contract. For
        `NEEDS_DECISION`, read the focused phase `### Continuation` Payload. If it has
        `Scope: phase` or routes to `procedures/phase-interrogate.md`, read and follow
        `procedures/phase-interrogate.md`. If it has `Scope: objective` or routes to
        `procedures/interrogate.md`, read and follow `procedures/interrogate.md`. If the payload
        does not identify a decision scope, stop and surface the reconciliation concern.
     3. Keep the phase focused and incomplete until explicit Step 8 approval/commit, regardless of
        the reconciliation route.

   With `--auto-commit`: auto-commit and return `PHASE_COMPLETE` per
   `references/phase-iterate-results.md` § Phase Iterate Result Blocks.
   1. Mark phase complete in index (`[x]`) and remove the focus marker (`*`).
   2. Read and follow `procedures/summarize.md` with `--auto` to ensure the summary reflects the
      final committed state.
   3. Compose the full revision description using the repo's version-control rules.
   4. Commit the phase with `jj commit -m "$desc"`.
   5. Return the structured result.

## Contracts

- Preserve verbatim: the two Step 1 nudges, the Step 1 objective-commit `jj commit` / `jj split`
  command shapes, the Step 2 no-work message ("Nothing to iterate.") and index entry
  `P. [ ] [Phase Name](./NN-phase-P.md) *`, the implement/verify dispatch prompts, the
  `No changes to verify.` contract string, the `ac_status` section→marker mapping, and the
  `PHASE_INCOMPLETE` / `PHASE_COMPLETE` blocks from `references/phase-iterate-results.md` § Phase
  Iterate Result Blocks.
- Loop ownership: phase-iterate owns the implement-verify loop (dispatch, AC status capture,
  termination) and lifecycle (commit, phase marking). AC derivation and annotation are now handled
  by `phase-verify`. Scoping is dispatched as an isolated subagent via `briefs/phase-scope.md`;
  phase-iterate uses the shared Auto-scope Dispatch auto-accept handler from
  `references/auto-scope-dispatch.md` § Dispatch.
- State passes between steps via `00-main.md` (ACs, phases index) and phase files (tasks, issues,
  approach, context, continuation).
- Never pause between steps. After each step completes, immediately proceed to the next unless the
  step requires user input (Steps 7 and 8 without `--auto-commit`, and blockers in Step 6). If any
  step fails or needs user input, stop and report.
- Never edit repo files directly — phase-iterate is orchestration only. All repo edits go through
  the dispatched implement/verify/reconciliation subagents, except: commits, the `00-main.md` index
  entry update in Step 2, and Step 8 approval/commit phase-index updates.
- Single-revision invariant (`references/workflow-invariants.md` § Invariants): all phase changes
  must live in `@` when verify runs — no intermediate `jj commit`, `jj new`, or `jj split` during
  the loop, so `jj diff` always captures the complete phase diff. Phase-iterate owns revision
  lifecycle.
- No iteration cap. Convergence is via dedup and monotonic progress (tasks go `[ ]` → `[x]` or
  `[!]`, never back).
- Handling user decisions when a step surfaces concerns and the user provides direction:
  - Adding tasks or addressing issues: re-run Step 4 (the loop picks up new tasks and open issues
    from the phase file).
  - Modifying ACs: read and follow `procedures/spec.md` with the requested changes.
  - Never process user decisions by editing repo files in the main thread.
