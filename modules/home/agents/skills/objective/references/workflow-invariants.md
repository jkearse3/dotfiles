# Workflow Invariants

Safety invariants shared by phase workflow procedures.

## Continuation Lifecycle

Apply this operation after a routed action has persisted its declared result:

1. Inspect the focused phase `### Continuation`.
2. If the continuation status matches the completed route and the result makes the next resume point
   unambiguous, remove `### Continuation` or replace it with the next required route.
3. If the next resume point is still ambiguous, update `### Continuation` with a precise Status,
   Source, Route, Summary, Clear when, and any needed Payload. Do not clear it.
4. Never clear or update continuation before the routed action's declared result write is complete.

When a phase-local route discovers that objective-level follow-up is required, update
`### Continuation` to the appropriate objective-level route only after the phase-local result is
persisted. The routed objective-level procedure owns any later `00-main.md` write.

## Invariants

- Preserve exact result tokens and strings consumed by callers.
- Preserve approval gates; do not turn user-approved steps into automatic writes.
- Subagents may write only what their brief's `## Write Permissions` section declares; anything not
  listed is denied.
- Preserve AC numbering and marker semantics.
- Preserve phase numbering and focus semantics.
- Route focused or phase-scoped implementation, continue, fix, tweak, complete, or work requests
  through `procedures/phase-iterate.md`; do not satisfy them with inline main-agent repo edits.
- Preserve the single-revision invariant: during implement/verify loops, all phase work stays in the
  current working-copy revision `@`; no command may move phase work out of `@`, change the current
  working-copy revision, or make `jj diff` stop representing the complete phase diff. The
  orchestrator owns revision lifecycle.
- Persist phase-local continuation before any procedure stops or routes away because unresolved
  phase-local follow-up cannot be completed in the current path.
- Clear phase-local continuation per § Continuation Lifecycle.
