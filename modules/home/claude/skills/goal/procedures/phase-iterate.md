# Phase Iterate

Orchestrate the inner loop: scope phase if needed, run the implement-verify loop inline, then enrich
and commit. Auto-scopes via scoping subagent when no phase is active.

Read these format references before executing this procedure:

- `references/phases.md`
- `references/templates.md`
- `references/acceptance-criteria.md`

## Arguments

Parse arguments for flags:

- `--auto-commit`: When set, Steps 6 and 8 return a structured `PHASE_INCOMPLETE` diagnostic on
  failure (blocked tasks, unresolved issues, or implement concerns) instead of stopping for user
  input, and Step 9 auto-commits and returns a structured `PHASE_COMPLETE` result instead of waiting
  for user review.

## Execution

Run these steps in order. Do not improvise or skip steps. Before executing each step, announce the
step number (e.g., "**Step 4: Run Implement**") to maintain orientation.

### Step 1: Load State

Read `.goals/_current/00-main.md` fresh (never rely on prior context).

- If no goal: nudge — "No active goal. Want me to load or create one?"
- If no ACs in `## Acceptance Criteria`: nudge — "No acceptance criteria defined yet. Want me to run
  `/goal spec`?"

**Goal commit** (one-time, before first phase): If no phases exist yet and goal files are tracked in
version control (check with `jj st`), commit the goal to preserve the spec as a checkpoint
independent of implementation. If the working copy contains only goal files, run
`jj commit -m "docs: <brief description>"`. If other files are also present, use
`jj split -m "docs: <brief description>" <goal-files>` to commit only the goal files.

### Step 2: Ensure Focused Phase

Find focused phase (`*` in `## Phases`).

- If focused phase exists: proceed to Step 3.
- If no focused phase: compute the phase-file path before dispatch per `references/templates.md` §
  New Phase → Compute phase-file inputs, then dispatch the scoping subagent via the `Task` tool with
  `subagent_type: "general-purpose"` and prompt:

  ```
  Read the file at ~/.claude/skills/goal/briefs/phase-scope.md and execute the instructions within it.

  goal_dir: <absolute path to goal directory>
  P: <phase number>
  NN: <sequence number, zero-padded>
  Phase file: <absolute path to phase file>
  ```

  - **On no work remaining**: report "All ACs satisfied. Nothing to iterate." and stop.
  - **On readiness issues**: surface them and stop.
  - **On phase proposal**: auto-accept. The subagent has already written the phase file at the
    provided path. Update `00-main.md` immediately by adding a linked index entry to `## Phases`:
    `P. [ ] [Phase Name](./NN-phase-P.md) *`. Do not wait for user approval.
  - Re-read `00-main.md` to pick up the new phase and proceed to Step 3.

### Step 3: Announce Scope

Locate the focused phase content using Phase Resolution (see format reference): if the `## Phases`
index entry has a markdown link, read that file; otherwise read the inline `## Phase N:` section in
`00-main.md`. Announce before executing:

- Phase name and number
- Pending tasks (count and brief list)
- Open issues (count)
- Targeted ACs (from task references)

### Step 4: Run Implement

Dispatch an implementation subagent via the `Task` tool with `subagent_type: "general-purpose"` and
prompt:

```
Read the file at ~/.claude/skills/goal/briefs/phase-implement.md and execute the instructions within it.

State file: <absolute path to phase file>
AC source: .goals/_current/00-main.md
```

**Always dispatch -- never skip based on task state.** The subagent decides whether work remains
(open issues need tasks even if existing tasks are complete).

If the subagent returns concerns requiring user input, stop and surface them.

**Check for blockers before verify:** Read the phase file. If any task is marked `[!]` and no
pending `[ ]` tasks remain, skip Step 5 and proceed directly to Step 6 (termination check). This
prevents verify from returning "no changes" and halting the loop before blockers are surfaced.

Otherwise, proceed to Step 5.

### Step 5: Run Verify

Dispatch a verify subagent via the `Task` tool with `subagent_type: "general-purpose"` and prompt:

```
Read the file at ~/.claude/skills/goal/briefs/phase-verify.md and execute the instructions within it.

State file: <absolute path to phase file>
AC source: .goals/_current/00-main.md
```

**Capture AC assessments**: When verify returns AC validation results (Validated, Needs
Verification, Regressions, Not Implemented sections), parse them into a structured `ac_status` list
of `{ac, status, evidence}` entries:

- `### Validated` entries → status `[x]`
- `### Needs Verification` entries → status `[~]`
- `### Regressions` entries → status `[!]`
- `### Not Implemented` entries → status `[ ]`

Store as the latest `ac_status` snapshot. Each subsequent AC-validation verify run replaces the
previous snapshot (latest-verify-wins).

**Snapshot preservation on non-AC-validation returns**: When verify returns a review-only summary
(new issues found) or "No changes to verify.", the existing `ac_status` snapshot is preserved
unchanged — do not clear or overwrite it. Only AC-validation returns update the snapshot. This
ensures Step 7a retains prior assessments when subsequent iterations short-circuit before AC
validation.

**Check verify result:**

- If verify found new issues (returned review-only summary with new issues): return to Step 4
  (implement will create tasks for new issues).
- If verify's summary contains the exact string `No changes to verify.` (contract with
  `briefs/phase-verify.md` Step 2 — do not change either without updating both): proceed to Step 6
  (termination check). Do not stop — state-file-only iterations still need completion handling.
- If verify completed AC validation:
  - Any `[~]` ACs not marked `(human)`: return to Step 4 (implement assesses testability)
  - All `[~]` are `(human)` or all ACs `[x]`: proceed to Step 6

### Step 6: Check Loop Termination

Read the phase file. The loop is complete when ALL of:

- All tasks are `[x]` (no pending `[ ]` tasks remain)
- No open issues exist (no `[ ]` issues remain)
- No tasks are blocked `[!]`

**If blocked tasks exist**: Stop and surface them to the user. Report which tasks are blocked and
why. Wait for user direction. If `--auto-commit`, return:

```
PHASE_INCOMPLETE
phase: <N>
reason: <blocked_tasks|unresolved_issues|implement_concerns>
details: <specific blockers or concerns>
```

**If not complete** (pending tasks or open issues remain but no blockers): Return to Step 4 for
another cycle.

**If complete**: Proceed to Step 7.

### Step 7: Post-Loop Enrichment

After the loop completes, run enrichment that requires goal-level context (AC status derivation and
annotation).

**7a. Derive AC status**: Use the `ac_status` snapshot captured in Step 5 as the primary source for
per-AC assessments. Each entry carries an AC number, status marker, and evidence note from verify's
last assessment.

- For ACs present in `ac_status`: use the status and evidence directly
- For ACs targeted by phase tasks but absent from `ac_status` (verify never assessed them): fall
  back to `[~]` (implemented, awaiting verification) based on task completion
- For ACs with `(human)` annotations in the phase file's `### Tasks`: preserve the `(human)` marker
  regardless of `ac_status`

**7b. AC evidence annotation**: Update `## Acceptance Criteria` in `00-main.md`:

- For each AC targeted by this phase, update the marker using the status from Step 7a
- Add evidence notes from `ac_status` entries. For ACs without verify evidence, derive brief notes
  from task descriptions and `(human)` annotations
  ```markdown
  1. [~] Component renders with buttons
     - src/components/header.tsx:98-112 renders all four buttons. 4 tests pass.
  2. [~] Export handles large files (human)
     - Needs manual testing with 10MB+ files.
  ```
- Evidence format: fully qualified paths (`src/path/file.ts:lines`), test results
- Preserve existing AC text and `(human)` annotations
- All status changes happen in a single edit

Proceed to Step 8.

### Step 8: Present Summary and Check Phase Termination

After steps complete, summarize:

- Tasks: total / completed / blocked (from phase file)
- Issues: total open (by severity)
- ACs: status changes, regressions (`[!]`), remaining `[~]` (with human/test distinction)
- Phase: complete or not

Phase is complete when ALL of:

- All phase tasks `[x]`
- All phase issues resolved

If complete:

- Mark phase complete in index (`[x]`)
- Remove focus marker (`*`)
- Collect targeted ACs from task references `(ACN, satisfy)` / `(ACN, codify)` for the summary
- Proceed to Step 9 (review and commit)

If `[~] (human)` ACs remain:

- Stop loop, present ACs needing human verification
- Phase can still be complete if tasks and issues are resolved — AC validation is a goal-level
  concern

If not complete for other reasons:

- **Without `--auto-commit`**: Stop. User decides whether to run another cycle.
- **With `--auto-commit`**: Return a structured diagnostic to the caller:
  ```
  PHASE_INCOMPLETE
  phase: <N>
  reason: <blocked_tasks|unresolved_issues|implement_concerns>
  details: <specific blockers or concerns>
  ```

### Step 9: Review and Commit

#### Without `--auto-commit`

After phase completion, announce that the phase is ready for review and wait for user approval
before committing:

1. **Announce**: "Phase N complete. Review the diff and approve when ready." Do NOT print or display
   the diff — the user will review it independently.
2. **Wait for user**: User reviews the uncommitted changes independently and either approves or
   requests tweaks.

**If user approves**:

1. Read and follow `procedures/summarize.md` with `--auto` to ensure summary reflects the final
   committed state.
2. Commit the phase with `jj commit -m "<conventional commit message>"`.
3. Note "Phase complete. Run `/goal phase-iterate` to scope and execute next phase."

**If user requests tweaks**:

1. Apply the requested changes in the working copy.
2. Re-run Step 4 (the implement-verify loop handles verification of the tweaks).

#### With `--auto-commit`

After phase completion, auto-commit and return a structured result:

1. Read and follow `procedures/summarize.md` with `--auto` to ensure summary reflects the final
   committed state.
2. Commit the phase with `jj commit -m "<conventional commit message>"`.
3. Return a structured result to the caller:
   ```
   PHASE_COMPLETE
   phase: <N>
   commit_message: <the conventional commit message used>
   ac_status: <list of AC number and new status, e.g. "AC1: [~], AC3: [~]">
   ```

## Rules

- The implement-verify loop runs inline via Task subagent dispatch. Phase-iterate owns the loop
  (dispatch, AC status capture, termination), post-loop enrichment (AC status derivation and
  annotation), and lifecycle (commit, phase marking).
- Scoping is dispatched as a Task subagent directly (isolated context). Scoping uses
  `briefs/phase-scope.md`; phase-iterate auto-accepts.
- State passes between steps via `00-main.md` (ACs, phases index) and phase files (tasks, issues,
  approach, context).
- If any step fails or needs user input, stop and report.
- **Never pause between steps.** After each step completes, immediately proceed to the next step. Do
  not wait for user input between steps unless explicitly required by the step (Steps 8 and 9
  without `--auto-commit`, and blockers in Step 6).
- **Never edit repo files directly.** Phase-iterate is orchestration only. All repo edits go through
  the dispatched implement/verify subagents (except for commits, `00-main.md` index entry update in
  Step 2, AC annotation in Step 7b, and user-directed tweaks in Step 9).
- **Single-revision invariant.** All phase changes must live in `@` when verify runs. No
  intermediate `jj commit`, `jj new`, or `jj split` during the loop — phase-iterate owns revision
  lifecycle. This ensures `jj diff` always captures the complete phase diff.
- **No iteration cap.** Convergence is via dedup and monotonic progress (tasks go `[ ]` to `[x]` or
  `[!]`, never back).

## Handling User Decisions

When a step surfaces concerns and user provides direction:

1. **Adding tasks or addressing issues**: Re-run Step 4 (the implement-verify loop picks up new
   tasks and open issues from the phase file)
2. **Modifying ACs**: Read and follow `procedures/spec.md` with the requested changes

Never process user decisions by editing repo files in the main thread.
