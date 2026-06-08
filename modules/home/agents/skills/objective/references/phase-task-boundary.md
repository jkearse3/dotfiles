# Phase Task Boundary

Phase task validity rules shared by phase-file creation and phase implementation callers.

## Phase Task Boundary

During a phase, implementation and verification operate on the current working-copy revision `@`.
All phase changes must remain in `@` until `phase-iterate` reaches its review/commit step.

Phase tasks must describe implementation, validation, cleanup, issue follow-up, or phase-relevant
investigation work. They must not ask agents to run VCS lifecycle operations that move work out of
`@`, change the current working-copy revision, or make `jj diff` stop representing the complete
phase diff. This includes committing, splitting, squashing, abandoning, rebasing, editing another
revision, creating a new working-copy revision, or checking out/switching revisions.

Phase tasks also must not perform objective lifecycle actions owned by `phase-iterate`, such as
marking phase index entries complete, refreshing objective summaries, routing continuation
lifecycle, or asking the user to review and approve the final diff. Approach or constraint text may
mention lifecycle ownership when it helps explain task boundaries.
