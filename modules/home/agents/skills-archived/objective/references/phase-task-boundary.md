# Phase Task Boundary

Phase task validity rules shared by phase-file creation and phase implementation
callers.

## Phase Task Boundary

During a phase, implementation and verification operate on the current
working-copy revision `@`. All phase changes must remain in `@` until
`phase-iterate` reaches its review/commit step.

Phase tasks must describe implementation, validation, cleanup, issue follow-up,
or phase-relevant investigation work. They must not ask agents to run VCS
lifecycle operations that move work out of `@`, change the current working-copy
revision, or make `jj diff` stop representing the complete phase diff. This
includes committing, splitting, squashing, abandoning, rebasing, editing another
revision, creating a new working-copy revision, or checking out/switching
revisions.

Phase tasks also must not perform objective lifecycle actions owned by
`phase-iterate`, such as marking phase index entries complete, refreshing
objective summaries, routing continuation lifecycle, or asking the user to
review and approve the final diff. Approach or constraint text may mention
lifecycle ownership when it helps explain task boundaries.

## Phase Size

Scope each phase as one independently valuable atomic commit. Prefer the
smallest cohesive change that can be reviewed, reverted, explained, and verified
on its own, but keep tightly coupled setup, caller updates, tests, and contract
changes together when splitting would add overhead without improving review or
rollback.

Split work when tasks describe separate user-visible behaviors, unrelated
cleanup, independent bug fixes, or changes that can be validated and reverted
without the rest of the phase. Keep work in one phase when splitting would leave
intermediate commits incomplete, require duplicated context, hide a
contract/caller relationship, or separate tests from the behavior they verify.

Use the "and" self-check as a prompt, not a mechanical rule: if "and" connects
independent outcomes, split the phase; if it connects coupled parts of one
outcome, keep them together.
