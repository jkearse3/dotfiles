# Implement Worker

Use only when dispatched by `procedures/implement.md` for `Status: active` with
`Next: implement`.

Read the state file fresh. Treat `## Acceptance Criteria` and `## Boundaries` as
authoritative. Use `## Context` to understand why the iteration exists. Use
`## Research` for findings, decisions, questions, and assumptions that shape
implementation. Treat `## Tasks` as mutation scratch tied back to ACs or
verify-owned issues where applicable.

Rules:

- Use the state file as the only source of iteration state.
- Perform only mutations explicitly authorized by the approved plan's ACs,
  approach, tasks, and boundaries.
- Repo file edits and revision lifecycle actions are allowed only when the
  approved plan explicitly permits them. Revision lifecycle actions include
  commit, describe, split, squash, switching bookmarks/branches, push, or moving
  work between revisions.
- Do not re-spec or expand requested work. Block if ACs or boundaries are
  incomplete, contradictory, or too ambiguous to implement safely.
- Stop before changes that violate boundaries or require user decisions.
- Treat AC `Check:` and `Details:` as part of the acceptance contract. `Check:`
  is the planned proof method, not action evidence or a task annotation.
- Implementation is an AC-scoped action/check/resolve loop. For each meaningful
  implementation slice, perform the smallest in-scope action needed for the
  referenced ACs, run or perform the relevant AC `Check:` when feasible within
  boundaries, and resolve the observed result before handoff.
- Fix or adjust in-scope check failures immediately when safe. If a failure
  cannot be resolved within the approved plan and boundaries, leave the task
  incomplete or blocked and record the direct blocker; do not route known
  implementation-time failures to verify as ready work.
- Do not mark ACs checked, change AC markers to `[x]`, `[~]`, or `[!]`, or write
  AC `Evidence:` lines. Verify owns AC markers and evidence.
- Do not create, update, or close normal `## Issues`; verify owns issue
  lifecycle. Only record direct blockers that require user input, protect
  safety, or enforce boundaries.
- Update the state file after each meaningful task, research, context, approach,
  candidate verification note, or direct blocker change.
- Do not mark the iteration review or complete; verify owns successful
  verification routing.

Steps:

1. Validate `Status: active` and `Next: implement`.
2. Inspect the repo enough to scope the next mutation slice safely.
3. Interpret `## Boundaries` as the iteration-specific contract, not a required
   schema.
4. Block before task scoping if AC coverage is incomplete, an AC lacks a
   feasible `Check:`, AC `Details:` contradict the requested work, required
   investigation/interrogation outcomes are missing, or boundaries do not give
   concrete rules for deciding whether the needed mutations are in scope and
   plan-authorized.
5. When boundaries allow discoverable scope, inspect only to identify files,
   systems, or behavior matching the stated relationship. Record durable
   findings when that affects implementation or later verification.
6. Treat a mutation as forbidden when the approved plan does not explicitly
   authorize it, boundaries do not directly permit it, inspection does not
   justify it, or it is only for unrelated workflow behavior.
7. Stop and block before ambiguous mutations, stop-before conditions, scope
   expansion, unauthorized revision lifecycle actions, or user decisions.
8. Create or refine a flat numbered task list just-in-time from AC statements,
   `Check:`, `Details:`, issues, context, research, and repo inspection.
   Annotate tasks with `(ACN, satisfy)`, `(ACN, codify)`, `(ACN, enhance)`, or
   `(IN)` where applicable. For each AC-scoped task, identify the relevant AC
   `Check:` methods that should be run or performed during implementation when
   feasible. `(ACN, codify)` means adding or updating repo checks or check
   assets for that AC; it does not replace, duplicate, or edit the AC's `Check:`
   line.
9. Execute pending tasks in a sensible order. After each meaningful AC-scoped
   action slice, run or perform the relevant planned checks when feasible within
   boundaries, then resolve the result before moving on.
10. Resolve implementation-time check failures by fixing or adjusting in-scope
    work. If resolution would violate boundaries, expand scope, require user
    input, or require unsafe action, mark the task `[!]`, record the direct
    blocker, and stop as blocked when user input is required.
11. Record candidate verification notes for checks run or performed during
    implementation, including the check path and observed result, but do not
    edit AC evidence.
12. Mark tasks `[x]` when complete with no known unresolved implementation-time
    check failure, `[!]` with a blocker when blocked, or `[ ]` when
    intentionally deferred. For verify-owned issues, use `(IN)` tasks to record
    fixes, but leave issue closure to verify.
13. Record durable repo findings under `### Findings`, decisions under
    `### Decisions`, unresolved blockers under `### Questions`, safe working
    assumptions under `### Assumptions`, and candidate verification notes
    without editing AC evidence.
14. Leave AC markers, AC evidence, and normal issue creation or closure for
    verify.
15. If user input is required, set `Status: blocked`, set `Next: none`, record
    the blocker, and stop.
16. If implementation has no known unresolved implementation-time check failures
    and is ready for verification, keep `Status: active`, set `Next: verify`,
    and return to the dispatcher.

Reread the state file before returning control to the dispatcher or stopping.
The state file is authoritative.
