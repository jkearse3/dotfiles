# Auto Iterate

Explicit autonomous outer loop: run a pre-flight confidence gate, then scope and
execute phases with `phase-iterate --auto-commit` until active AC implementation
work is complete or a stop condition requires user input.

If the user request is focused on implementing, continuing, fixing, tweaking,
completing, or working on a current phase or other phase-scoped slice, satisfy
it by reading and following `procedures/phase-iterate.md`; do not perform inline
main-agent repo edits from this procedure.

## References

- `references/current-objective.md` — Load Current Objective.
- `references/auto-scope-dispatch.md` — Auto-scope Dispatch.
- `references/phase-index.md` — Phase Resolution.
- `references/phase-iterate-results.md` — Phase Iterate Result Blocks.
- `references/workflow-invariants.md` — approval-gate, continuation, and
  orchestration invariants.
- `references/ac-markers.md` — AC marker semantics.

## Steps

Run in order. Do not improvise or skip steps.

1. Load state. Read `.objectives/_current/00-main.md` fresh (never rely on prior
   context) per `references/current-objective.md` § Load Current Objective,
   including its no-objective nudge.
   - If no ACs in `## Acceptance Criteria`: nudge — "No acceptance criteria
     defined yet. Want me to run `/objective spec`?" Stop before the confidence
     gate.

2. Pre-flight confidence gate. Validate the spec is ready for autonomous
   execution. Check each condition and collect all gaps before stopping.

   Research completeness:
   - All Questions under `### Questions` resolved (no unchecked `[ ]` items).
   - All Assumptions under `### Assumptions` validated (no unchecked `[ ]`
     items).

   Approach quality:
   - `## Approach` exists and is not placeholder text ("No approach yet", empty,
     etc.).
   - An agent can scope phases and execute without asking clarifying questions:
     - Sequencing constraints stated.
     - Architectural decisions made (not deferred).
     - Key patterns/libraries identified.
   - Flag as a gap if any of these would require human input to resolve.

   AC verifiability:
   - Each AC is verifiable by code inspection or tests — not vague ("works
     well", "is fast").
   - ACs requiring human judgment are explicitly marked `(human)`.
   - No `[!]` regressions present.

   If any check fails: list specific gaps and stop. Do not enter the autonomous
   loop.

3. Enter autonomous loop. Re-read `.objectives/_current/00-main.md` at the start
   of each iteration, then go to Step 4.

4. Ensure one focused phase for this iteration. Read the `## Phases` index.
   - If exactly one phase has `[focus]`: go to Step 5.
   - If multiple phases have `[focus]`: stop with an incoherent-scope diagnostic
     listing them.
   - If no phase has `[focus]` and one or more phases are `[ ]`: add `[focus]`
     to the lowest-numbered `[ ]` phase, re-read `00-main.md`, and return to
     Step 4.
   - If no phase has `[focus]` and no phase is `[ ]` and no active `[ ]` ACs
     remain (excluding `[-]` invalidated ACs): go to Step 6.
   - If no phase has `[focus]`: run `references/auto-scope-dispatch.md` §
     Dispatch with these procedure-specific results:
     - No work remaining: re-read `00-main.md`. If active `[ ]` ACs remain, stop
       with a no-scope readiness diagnostic. Otherwise go to Step 6.
     - Readiness issues: surface them and stop.
     - Phase proposal: use the default Phase proposal acceptance from the
       dispatch reference to add `P. [ ] [Phase Name](./NN-phase-P.md) [focus]`
       to `00-main.md`, then re-read `00-main.md` and return to Step 4.

5. Run focused phase automatically. Locate the focused phase file per
   `references/phase-index.md` § Phase Resolution. Read and follow
   `procedures/phase-iterate.md` with `--auto-commit`.

   Handle the returned block per `references/phase-iterate-results.md` § Phase
   Iterate Result Blocks:
   - On `PHASE_COMPLETE`: re-read `.objectives/_current/00-main.md`. If any
     `[!]` regressions exist, stop with a diagnostic listing the regressed ACs.
     Otherwise return to Step 3.
   - On `PHASE_INCOMPLETE`: re-read `.objectives/_current/00-main.md`, resolve
     the focused phase, and read its `### Continuation` section when present.
     Stop with a diagnostic reporting the phase number, reason, and specific
     blockers or concerns. If continuation exists, surface Status, Source,
     Route, Summary, Clear when, and any Payload as resume state. Do not write,
     clear, or otherwise take ownership of `### Continuation`.

6. Completion handoff. When no phase is focused, no phase is `[ ]`, and no
   active `[ ]` ACs remain (all are `[x]`, `[~]`, or `[-]`), list any remaining
   `[~] (human)` ACs that need user sign-off. Announce: "All phases complete.
   Run `/objective finalize` to write the PR-ready summary."

## Contracts

- Preserve verbatim: the no-AC nudge, the pre-flight gate checks, the
  `phase-iterate --auto-commit` invocation, the `PHASE_COMPLETE` /
  `PHASE_INCOMPLETE` handling per `references/phase-iterate-results.md` § Phase
  Iterate Result Blocks, and the completion handoff announcement.
- Explicit autonomy: this procedure is the named full-objective autonomous phase
  loop. One-phase `/objective iterate` must not call this procedure implicitly.
- Stop immediately on readiness issues, blocked tasks, unresolved issues,
  implementation concerns, spec-change requirements, regressions, incoherent
  phase scope, continuation routes, or any other user-input need. Do not retry
  or continue to another phase after such a stop.
- Finalization remains explicit: never run closeout from this procedure. Direct
  the caller to `/objective finalize` when active phase work is complete.
- Phase-scoped work routing: focused
  implementation/continue/fix/tweak/complete/work requests are delegated to
  `procedures/phase-iterate.md`; this procedure must not create a second
  implementation path.
- `[~] (human)` ACs do not block the autonomous loop — they are deferred and
  listed at completion.
- Resumable: re-invoking `/objective auto-iterate` after a stop reads
  `00-main.md`, finds completed phases already `[x]`, resumes the focused phase
  if one exists, focuses the lowest-numbered pending phase when phase backlog
  exists, or scopes one next phase when work remains.
