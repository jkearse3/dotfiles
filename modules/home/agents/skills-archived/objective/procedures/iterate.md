# Iterate

Public one-phase orchestrator: preflight the objective, ensure exactly one phase is focused by
scoping the next phase when needed, then run the focused phase engine through the manual review
path.

If the user request is focused on implementing, continuing, fixing, tweaking, completing, or working
on a current phase or other phase-scoped slice, satisfy it by reading and following
`procedures/phase-iterate.md`; do not perform inline main-agent repo edits from this procedure.

## References

- `references/current-objective.md` — Load Current Objective.
- `references/auto-scope-dispatch.md` — Auto-scope Dispatch.
- `references/phase-index.md` — Phase Resolution.
- `references/workflow-invariants.md` — approval-gate, focus, and orchestration invariants.
- `references/ac-markers.md` — AC marker semantics.

## Steps

Run in order. Do not improvise or skip steps.

1. Load state. Read `.objectives/_current/00-main.md` fresh (never rely on prior context) per
   `references/current-objective.md` § Load Current Objective, including its no-objective nudge.
   - If no ACs in `## Acceptance Criteria`: nudge — "No acceptance criteria defined yet. Want me to
     run `/objective spec`?" and stop.

2. Pre-flight readiness gate. Validate the spec is ready for bounded one-phase execution. Check each
   condition and collect all gaps before stopping.

   Research completeness:
   - All Questions under `### Questions` resolved (no unchecked `[ ]` items).
   - All Assumptions under `### Assumptions` validated (no unchecked `[ ]` items).

   Approach quality:
   - `## Approach` exists and is not placeholder text ("No approach yet", empty, etc.).
   - An agent can scope one phase and execute without asking clarifying questions:
     - Sequencing constraints stated.
     - Architectural decisions made (not deferred).
     - Key patterns/libraries identified.
   - Flag as a gap if any of these would require human input to resolve.

   AC verifiability:
   - Each AC is verifiable by code inspection or tests — not vague ("works well", "is fast").
   - ACs requiring human judgment are explicitly marked `(human)`.
   - No `[!]` regressions present.

   If any check fails: list specific gaps and stop. Do not scope or implement a phase.

3. Ensure one focused phase. Read the `## Phases` index.
   - If exactly one phase has `*`: go to Step 4.
   - If multiple phases have `*`: stop with a diagnostic listing them. Tell the caller to keep
     exactly one `*`, or run `/objective phase-scope` after resolving the index.
   - If no phase has `*` and one or more phases are `[ ]`: add `*` to the lowest-numbered `[ ]`
     phase, re-read `00-main.md`, and return to Step 3.
   - If no phase has `*` and no active `[ ]` ACs remain (excluding `[-]` invalidated ACs): go to
     Step 6.
   - If no phase has `*` and active `[ ]` ACs remain: go to Step 3a.

   Step 3a: scope the next phase. Run `references/auto-scope-dispatch.md` § Dispatch with these
   procedure-specific results:
   - No work remaining: re-read `00-main.md`. If active `[ ]` ACs remain, stop with a no-scope
     readiness diagnostic. Otherwise go to Step 6.
   - Readiness issues: surface them and stop.
   - Phase proposal: use the default Phase proposal acceptance from the dispatch reference to add
     `P. [ ] [Phase Name](./NN-phase-P.md) *` to `00-main.md`, then re-read `00-main.md` and return
     to Step 3.

4. Run focused phase. Locate the focused phase file per `references/phase-index.md` § Phase
   Resolution. Read and follow `procedures/phase-iterate.md` without `--auto-commit`.

   The focused phase engine owns implementation, verification, review approval, commit, and phase
   index completion. If it stops for blockers, unresolved issues, implementation concerns,
   continuation routing, review feedback, or user approval, surface the stop reason and stop. Do not
   retry, auto-commit, or start another phase.

5. Post-phase stop. After `procedures/phase-iterate.md` completes its manual review/commit outcome,
   re-read `.objectives/_current/00-main.md`.
   - If any `[!]` regressions exist: stop with a diagnostic listing the regressed ACs.
   - If any phase index entries remain `[ ]`: report that the phase outcome is complete and stop. Do
     not direct the caller to `/objective finalize` while pending phases remain.
   - If active `[ ]` ACs remain: report that the phase outcome is complete and stop. Do not begin
     the next phase automatically.
   - If no active `[ ]` ACs remain: go to Step 6.

6. Completion handoff. When no phase is `[ ]` and no active `[ ]` ACs remain (all are `[x]`, `[~]`,
   or `[-]`), list any remaining `[~] (human)` ACs that need user sign-off. Announce: "All phases
   complete. Run `/objective finalize` to write the PR-ready summary."

## Contracts

- Preserve verbatim: the no-AC nudge, the default Auto-scope Dispatch acceptance shape
  `P. [ ] [Phase Name](./NN-phase-P.md) *`, and the completion handoff announcement.
- One-phase boundary: this procedure advances at most one phase. It focuses at most one existing
  pending phase (the lowest-numbered `[ ]` phase when several are pending without focus) or scopes
  at most one new phase, delegates to `procedures/phase-iterate.md` once, and stops after that
  phase's review/commit or blocker outcome.
- Manual review path: call `procedures/phase-iterate.md` without `--auto-commit`. Do not commit from
  this procedure except through the focused phase engine's approval-gated lifecycle.
- Finalization remains explicit: never run closeout from this procedure. Direct the caller to
  `/objective finalize` when active phase work is complete.
- Phase-scoped work routing: focused implementation/continue/fix/tweak/complete/work requests are
  delegated to `procedures/phase-iterate.md`; this procedure must not create a second implementation
  path.
- `[~] (human)` ACs do not block the one-phase run — they are listed at completion for user
  sign-off.
- Resumable: re-invoking `/objective iterate` after a stop reads `00-main.md`, preserves completed
  phases already `[x]`, resumes the focused phase if one exists, focuses the lowest-numbered pending
  phase when phase backlog exists, or scopes one next phase when work remains.
