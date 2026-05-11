# Phase Scope

Scope the next phase when none is active. Orchestrates a scoping subagent, presents its proposal for
user approval, and supports interactive refinement by re-dispatching a fresh scoping subagent per
feedback round; prior-round context is recovered from the phase file written on the previous round,
not carried in the prompt.

Read these format references before executing this procedure:

- `references/phases.md`
- `references/templates.md`

## Steps

1. **Load state**: Read `.goals/_current/00-main.md`
   - If no goal: nudge — "No active goal. Want me to load or create one?"
   - If no ACs in `## Acceptance Criteria`: nudge — "No acceptance criteria defined yet. Want me to
     run `/goal spec`?"

2. **Find focused phase** (`*` in `## Phases`):
   - If focused phase exists: stop, say "Phase already in focus. Run `/goal phase-iterate` to
     execute."
   - If no focused phase: continue

3. **Gate check**: All existing phases must be `[x]` or `[-]`. If any phase is `[ ]` without `*`,
   stop: "Incomplete phase exists without focus. Mark it `[x]`, `[-]`, or add `*` to resume."

4. **Compute phase-file path** (before dispatch, reused across refinement rounds): follow
   `references/templates.md` § New Phase → Compute phase-file inputs. Hold these four values
   (`goal_dir`, `P`, `NN`, path) for reuse in Steps 5, 7, and 8.

5. **Dispatch scoping subagent**: Dispatch a subagent with:
   - `prompt`:

   ```
   Read the file at ~/.claude/skills/goal/briefs/phase-scope.md and execute the instructions within it.

   goal_dir: <absolute path to goal directory>
   P: <phase number>
   NN: <sequence number, zero-padded>
   Phase file: <absolute path to phase file>
   ```

 6. **Handle subagent return**:

    The subagent returns structured output. Three cases:
    - **No work remaining**: Report "No phase to scope." and stop.
    - **Readiness issues**: Surface each issue to the user with the subagent's suggested resolution.
      Stop and wait for user to address.
    - **Phase proposal**: The subagent has written the phase file at the provided path. Read that
      file and present its contents (name, approach, tasks) plus the targeted ACs from the return
      shape. Wait for approval.

7. **Interactive refinement loop**:
   - **User approves**: Proceed to step 8.
   - **User requests adjustments**: Re-dispatch a fresh scoping subagent, reusing the same
     `goal_dir`, `P`, `NN`, and path from Step 4 so the subagent overwrites the same phase file in
     place:
     - `prompt`: the standard brief invocation plus the reused path inputs, followed by the user's
       feedback. The brief's Step 1 reads the existing phase file at the provided path for prior
       approach/tasks context, so the prompt does not need to restate it. Use this shape:

     ```
     Read the file at ~/.claude/skills/goal/briefs/phase-scope.md and execute the instructions within it.

     goal_dir: <absolute path to goal directory>
     P: <phase number>
     NN: <sequence number, zero-padded>
     Phase file: <absolute path to phase file>

     User feedback:
     <verbatim user feedback>

     Produce a revised proposal that addresses the feedback. Overwrite the phase file at the
     provided path.
     ```

      Handle the re-dispatch return:
      - **No work remaining**: Report "No phase to scope." and stop the loop.
     - **Readiness issues**: Surface each issue to the user with the subagent's suggested resolution
       and stop the loop.
     - **Phase proposal**: Re-read the phase file and present the updated proposal. Repeat this step
       until approved or user abandons.

     Each round dispatches a new subagent — there is no session continuity; the prior draft is
     recovered by the brief's Step 1 read of the existing phase file.

8. **Register phase in index** (on approval):
   - Add linked entry to `## Phases` in `00-main.md`: `P. [ ] [Phase Name](./NN-phase-P.md) *`
   - Move `*` from any previously focused phase to the new entry
   - Present summary confirming phase creation
