# Phase Scope

Scope the next phase when none is active: orchestrate a scoping subagent, present its proposal for
user approval, and refine interactively by re-dispatching a fresh scoping subagent per feedback
round.

## References

- `references/contracts.md` — file conventions, Auto-scope Dispatch, and invariants.
- `references/phases.md` — phase numbering and section layout.
- `references/templates.md` — New Phase (compute phase-file inputs before dispatch).

## Steps

1. Load state. Read `.objectives/_current/00-main.md`.
   - If no objective: nudge — "No active objective. Want me to load or create one?"
   - If no ACs in `## Acceptance Criteria`: nudge — "No acceptance criteria defined yet. Want me to
     run `/objective spec`?"

2. Find focused phase (`*` in `## Phases`).
   - If a focused phase exists: stop — "Phase already in focus. Run `/objective phase-iterate` to
     execute."
   - If none: go to Step 3.

3. Gate check. All existing phases must be `[x]` or `[-]`. If any phase is `[ ]` without `*`, stop —
   "Incomplete phase exists without focus. Mark it `[x]`, `[-]`, or add `*` to resume."

4. Compute phase-file inputs. Follow `references/templates.md` § New Phase → Compute phase-file
   inputs. Hold the four values (`objective_dir`, `P`, `NN`, path) for reuse across Steps 5, 7, and
   8 — the same inputs scope every refinement round so the subagent overwrites the same file in
   place.

5. Dispatch scoping subagent. Run `references/contracts.md` § Auto-scope Dispatch with these
   procedure-specific results:
   - No work remaining: report "No phase to scope." and stop.
   - Readiness issues: surface each issue with the subagent's suggested resolution; stop and wait
     for the user to address them.
   - Phase proposal: the subagent has written the phase file at the computed path. Read it and
     present its contents (name, approach, tasks) plus the targeted ACs from the return shape. Wait
     for approval — do not auto-accept.

6. Refinement loop.
   - User approves: go to Step 7.
   - User requests adjustments: re-dispatch a fresh scoping subagent, reusing `objective_dir`, `P`,
     `NN`, and path from Step 4. The brief's Step 1 reads the existing phase file for prior
     approach/tasks context, so the prompt does not restate it. Append the user's feedback:

     ```text
     Read the file at ~/.claude/skills/objective/briefs/phase-scope.md and execute the instructions within it.

     objective_dir: <absolute path to objective directory>
     P: <phase number>
     NN: <sequence number, zero-padded>
     Phase file: <absolute path to phase file>

     User feedback:
     <verbatim user feedback>

     Produce a revised proposal that addresses the feedback. Overwrite the phase file at the
     provided path.
     ```

     Handle the return:
     - No work remaining: report "No phase to scope." and stop the loop.
     - Readiness issues: surface each issue with the subagent's suggested resolution; stop the loop.
     - Phase proposal: re-read the phase file and present the updated proposal. Repeat until
       approved or abandoned.

7. Register phase in index (on approval). Add a linked entry to `## Phases` in `00-main.md`:
   `P. [ ] [Phase Name](./NN-phase-P.md) *`. Move `*` from any previously focused phase to the new
   entry. Present a summary confirming phase creation.

## Contracts

- Preserve verbatim: the two nudges, the focused-phase stop string, the gate-check stop string, the
  Auto-scope Dispatch no-work message ("No phase to scope."), the index entry
  `P. [ ] [Phase Name](./NN-phase-P.md) *`, and the refinement-loop dispatch prompt.
- This procedure presents the proposal and waits for approval — it does not auto-accept (unlike
  `phase-iterate` Step 2).
- Each refinement round dispatches a new subagent. There is no session continuity; the prior draft
  is recovered by the brief's Step 1 read of the existing phase file.
