# Phase Reconcile Brief

Classify non-auto Step 8 review feedback and persist the next route in the focused phase file.

## References

- `references/contracts.md` — file conventions, Reconciliation Result Contract, and invariants
  (caller-token preservation, continuation persistence, and write boundaries).
- `references/phases.md` — `### Continuation` labels.
- `references/templates.md` — § Phase Task Boundary for direct task append validity.

## Arguments

The orchestrator provides these inputs in the prompt:

- `State file` — absolute path to the focused phase file.
- `AC source` — `.objectives/_current/00-main.md`, used as read-only context.
- `Review feedback` — the user's Step 8 feedback, copied verbatim.

## Write Permissions

- Write only the phase file at the provided `State file` path.

## Steps

1. Load state. Read the phase file at `State file`:
   - `### Context` — phase intent.
   - `### Approach` — strategy and constraints.
   - `### Tasks` — completed and pending work.
   - `### Issues` — existing follow-up and dedup targets.
   - `### Continuation` — existing route state, if present.

   Read the AC source file `## Acceptance Criteria` section as read-only context. Do not modify the
   AC source file.

2. Classify each feedback item. Split `Review feedback` into itemized dispositions. For each item,
   choose one disposition:
   - `NO_ACTION` — feedback is approval-like, already satisfied, duplicate of resolved work, or
     needs no phase-file update.
   - `NEEDS_USER_INPUT` — feedback is ambiguous, conflicts with existing instructions, or requires a
     human decision before work can proceed.
   - `NEEDS_IMPLEMENTATION` — feedback is in scope and can be addressed by another Step 4
     implement-verify cycle.
   - `NEEDS_RESEARCH` — objective-wide research is needed before implementation can proceed.
   - `NEEDS_DECISION` — objective-wide or phase-local decisions are needed before implementation can
     proceed. The disposition must include an explicit `Scope: objective` or `Scope: phase`.
   - `SPEC_CHANGE_REQUIRED` — ACs, objective approach, phase scope, or task-to-AC mappings may need
     to change before implementation continues.

3. Persist implementation follow-up. For every `NEEDS_IMPLEMENTATION` item:
   - Append to `### Issues` by default using the next sequential issue number:
     `N. [ ] (human, medium): <feedback summary>`.
   - Append directly to `### Tasks` only when the feedback is already an unambiguous mechanical work
     item with a clear completion condition and satisfies `references/templates.md` § Phase Task
     Boundary.
   - If feedback requests a lifecycle action that violates the boundary, classify it as
     `NEEDS_USER_INPUT` unless it is approval-like feedback already handled by `NO_ACTION`.
   - Deduplicate against existing open issues and pending tasks before appending.

4. Select one top-level status. If dispositions are mixed, route blockers before implementation in
   this priority order:
   - `NEEDS_USER_INPUT`
   - `SPEC_CHANGE_REQUIRED`
   - `NEEDS_RESEARCH`
   - `NEEDS_DECISION`
   - `NEEDS_IMPLEMENTATION`
   - `NO_ACTION`

5. Persist continuation when routing away. If the top-level status cannot immediately return to Step
   8 approval (`NO_ACTION`) or Step 4 implementation (`NEEDS_IMPLEMENTATION`), write or update
   `### Continuation` in the phase file using `references/phases.md` continuation labels:
   - `Status`: the top-level status.
   - `Source`: `phase-iterate Step 8 reconciliation`.
   - `Route`: the deterministic next route from the status (see `references/contracts.md` §
     Reconciliation Result Contract).
   - `Summary`: concise summary of the unresolved feedback.
   - `Clear when`: the routed procedure has persisted its result and the next resume point is
     unambiguous.
   - `Payload`: include itemized dispositions or verbatim feedback when needed for recovery. For
     `NEEDS_RESEARCH`, include enough topic/context for `procedures/investigate.md` to derive the
     default objective-level research topic. For `NEEDS_DECISION`, include `Scope: objective` or
     `Scope: phase`, the routed procedure name, and enough topic/context for that procedure to
     derive the default decision topic.

   Do not write `### Continuation` for `NO_ACTION` or `NEEDS_IMPLEMENTATION`, because those statuses
   return directly to Step 8 approval or Step 4 implementation.

6. Return summary. Return the `## Result: Reconciliation Summary` block from
   `references/contracts.md` § Reconciliation Result Contract.

## Contracts

### Rules

- Preserve the user's feedback verbatim in the result summary when exact wording affects the next
  route.
- The phase file is the single source of truth for reconciliation state.
- Never modify repo implementation files, `00-main.md`, or any phase file other than `State file`.
- Preserve exact top-level status tokens; callers route on these strings.
