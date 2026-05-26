# Phase Iterate

Orchestrate the inner loop: scope a phase if none is active, run the implement-verify loop inline,
then enrich AC status and commit.

## Arguments

- `--auto-commit`: Steps 6 and 8 return a structured `PHASE_INCOMPLETE` diagnostic on failure
  (blocked tasks, unresolved issues, or implement concerns) instead of stopping for user input, and
  Step 9 auto-commits and returns a structured `PHASE_COMPLETE` result instead of waiting for user
  review.

## References

- `references/contracts.md` — file conventions, Auto-scope Dispatch, and invariants (single-revision
  rule).
- `references/phases.md` — Phase Resolution (locate focused phase content).
- `references/templates.md` — New Phase (compute phase-file inputs before dispatch).
- `references/acceptance-criteria.md` — AC marker and evidence semantics.

## Steps

Run in order. Do not improvise or skip steps. Announce each step number before executing it (e.g.,
"Step 4: Run Implement") to maintain orientation.

1. Load state. Read `.objectives/_current/00-main.md` fresh (never rely on prior context).
   - If no objective: nudge — "No active objective. Want me to load or create one?"
   - If no ACs in `## Acceptance Criteria`: nudge — "No acceptance criteria defined yet. Want me to
     run `/objective spec`?"

   Objective commit (one-time, before first phase): if no phases exist yet and objective files are
   tracked in version control (check with `jj st`), commit the objective to preserve the spec as a
   checkpoint independent of implementation. If the working copy contains only objective files, run
   `jj commit -m "docs: <brief description>"`. If other files are also present, use
   `jj split -m "docs: <brief description>" <objective-files>` to commit only the objective files.

2. Ensure focused phase. Find the focused phase (`*` in `## Phases`).
   - If a focused phase exists: go to Step 3.
   - If none: run `references/contracts.md` § Auto-scope Dispatch with these procedure-specific
     results:
     - No work remaining: report "Nothing to iterate." and stop.
     - Readiness issues: surface them and stop.
     - Phase proposal: auto-accept (no user approval). The subagent has already written the phase
       file at the computed path. Update `00-main.md` immediately by adding a linked index entry to
       `## Phases`: `P. [ ] [Phase Name](./NN-phase-P.md) *`. Then re-read `00-main.md` to pick up
       the new phase and go to Step 3.

3. Announce scope. Locate the focused phase content per `references/phases.md` § Phase Resolution:
   if the index entry has a markdown link, read that file; otherwise read the inline `## Phase N:`
   section in `00-main.md`. Announce before executing:
   - Phase name and number.
   - Pending tasks (count and brief list).
   - Open issues (count).
   - Targeted ACs (from task references).

4. Run implement. Dispatch an implementation subagent with prompt:

   ```text
   Read the file at ~/.claude/skills/objective/briefs/phase-implement.md and execute the instructions within it.

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
   Read the file at ~/.claude/skills/objective/briefs/phase-verify.md and execute the instructions within it.

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
     for user direction. With `--auto-commit`, return instead:

     ```text
     PHASE_INCOMPLETE
     phase: <N>
     reason: <blocked_tasks|unresolved_issues|implement_concerns>
     details: <specific blockers or concerns>
     ```

   - If not complete (pending tasks or open issues remain but no blockers): return to Step 4 for
     another cycle.
   - If complete: go to Step 7.

7. Post-loop enrichment. Run enrichment that requires objective-level context (AC status derivation
   and annotation).

   7a. Derive AC status. Use the `ac_status` snapshot from Step 5 as the primary source for per-AC
   assessments. Each entry carries an AC number, status marker, and evidence note from verify's last
   assessment.
   - ACs present in `ac_status`: use the status and evidence directly.
   - ACs targeted by phase tasks but absent from `ac_status` (verify never assessed them):
     - All referencing tasks are `(enhance)`: preserve the existing marker from `00-main.md` (the AC
       was already satisfied before this phase — enhancement doesn't change its status).
     - Otherwise: fall back to `[~]` (implemented, awaiting verification) based on task completion.
   - ACs with `(human)` annotations in the phase file's `### Tasks`: preserve the `(human)` marker
     regardless of `ac_status`.

   7b. AC evidence annotation. Update `## Acceptance Criteria` in `00-main.md`:
   - For each AC targeted by this phase, update the marker using the status from Step 7a.
   - Add evidence notes from `ac_status` entries. For ACs without verify evidence, derive brief
     notes from task descriptions and `(human)` annotations:

     ```markdown
     1. [~] Component renders with buttons
        - src/components/header.tsx:98-112 renders all four buttons. 4 tests pass.
     2. [~] Export handles large files (human)
        - Needs manual testing with 10MB+ files.
     ```

   - Evidence format: fully qualified paths (`src/path/file.ts:lines`), test results.
   - Preserve existing AC text and `(human)` annotations.
   - All status changes happen in a single edit.

   Go to Step 8.

8. Present summary and check phase termination. Summarize:
   - Tasks: total / completed / blocked (from phase file).
   - Issues: total open (by severity).
   - ACs: status changes, regressions (`[!]`), remaining `[~]` (with human/test distinction).
   - Phase: complete or not.

   Phase is complete when ALL of:
   - All phase tasks `[x]`.
   - All phase issues resolved.

   - If complete:
     - Mark phase complete in index (`[x]`).
     - Remove focus marker (`*`).
     - Collect targeted ACs from task references (`(ACN, satisfy)` / `(ACN, codify)` /
       `(ACN, enhance)`) for the summary.
     - Go to Step 9 (review and commit).
   - If `[~] (human)` ACs remain: stop the loop and present the ACs needing human verification. The
     phase can still be complete if tasks and issues are resolved — AC validation is an
     objective-level concern.
   - If not complete for other reasons:
     - Without `--auto-commit`: stop. User decides whether to run another cycle.
     - With `--auto-commit`: return a structured diagnostic:

       ```text
       PHASE_INCOMPLETE
       phase: <N>
       reason: <blocked_tasks|unresolved_issues|implement_concerns>
       details: <specific blockers or concerns>
       ```

9. Review and commit.

   Without `--auto-commit`: announce that the phase is ready for review and wait for user approval
   before committing.
   1. Announce: "Phase N complete. Review the diff and approve when ready." Do NOT print or display
      the diff — the user reviews it independently.
   2. Wait for the user, who either approves or requests tweaks.
   - If the user approves:
     1. Read and follow `procedures/summarize.md` with `--auto` to ensure the summary reflects the
        final committed state.
     2. Commit the phase with `jj commit -m "<conventional commit message>"`.
     3. Note "Phase complete. Run `/objective phase-iterate` to scope and execute next phase."
   - If the user requests tweaks:
     1. Apply the requested changes in the working copy.
     2. Re-run Step 4 (the implement-verify loop verifies the tweaks).

   With `--auto-commit`: auto-commit and return a structured result.
   1. Read and follow `procedures/summarize.md` with `--auto` to ensure the summary reflects the
      final committed state.
   2. Commit the phase with `jj commit -m "<conventional commit message>"`.
   3. Return:

      ```text
      PHASE_COMPLETE
      phase: <N>
      commit_message: <the conventional commit message used>
      ac_status: <list of AC number and new status, e.g. "AC1: [~], AC3: [~]">
      ```

## Contracts

- Preserve verbatim: the two Step 1 nudges, the Step 1 objective-commit `jj commit` / `jj split`
  invocations, the Step 2 no-work message ("Nothing to iterate.") and index entry
  `P. [ ] [Phase Name](./NN-phase-P.md) *`, the implement/verify dispatch prompts, the
  `No changes to verify.` contract string, the `ac_status` section→marker mapping, the
  `PHASE_INCOMPLETE` / `PHASE_COMPLETE` blocks and their fields, and the Step 9
  `jj commit -m "<conventional commit message>"` invocation.
- Loop ownership: phase-iterate owns the implement-verify loop (dispatch, AC status capture,
  termination), post-loop enrichment (AC status derivation and annotation), and lifecycle (commit,
  phase marking). Scoping is dispatched as an isolated subagent via `briefs/phase-scope.md`;
  phase-iterate auto-accepts.
- State passes between steps via `00-main.md` (ACs, phases index) and phase files (tasks, issues,
  approach, context).
- Never pause between steps. After each step completes, immediately proceed to the next unless the
  step requires user input (Steps 8 and 9 without `--auto-commit`, and blockers in Step 6). If any
  step fails or needs user input, stop and report.
- Never edit repo files directly — phase-iterate is orchestration only. All repo edits go through
  the dispatched implement/verify subagents, except: commits, the `00-main.md` index entry update in
  Step 2, AC annotation in Step 7b, and user-directed tweaks in Step 9.
- Single-revision invariant (`references/contracts.md` § Invariants): all phase changes must live in
  `@` when verify runs — no intermediate `jj commit`, `jj new`, or `jj split` during the loop, so
  `jj diff` always captures the complete phase diff. Phase-iterate owns revision lifecycle.
- No iteration cap. Convergence is via dedup and monotonic progress (tasks go `[ ]` → `[x]` or
  `[!]`, never back).
- Handling user decisions when a step surfaces concerns and the user provides direction:
  - Adding tasks or addressing issues: re-run Step 4 (the loop picks up new tasks and open issues
    from the phase file).
  - Modifying ACs: read and follow `procedures/spec.md` with the requested changes.
  - Never process user decisions by editing repo files in the main thread.
