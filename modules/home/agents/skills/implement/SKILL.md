---
name: implement
description: >-
  Executes authorized persistent repository changes from scope alignment through implementation,
  verification, revision finalization, and independent diff review. Use for coding, configuration,
  documentation, tests, migrations, or other repository edits; not for read-only investigation,
  planning without execution, review-only requests, external-system operations, or publication.
argument-hint: "<authorized change or ready plan>"
---

# Implement

Carry an authorized repository change from an aligned request to a verified, finalized,
independently reviewed result without creating persistent workflow state.

## Input

```text
$ARGUMENTS
```

Use the arguments, the user's request, and any current ready plan as the implementation boundary. If
they do not identify an authorized persistent change, stop and ask for the missing authority or
scope. A plan describes work but does not authorize it.

## Preconditions

Before editing:

1. Confirm that implementation is requested or clearly implied. Treat investigation, explanation,
   proposals, planning, and review as read-only unless the user also authorized changes.
2. Establish a concise working plan covering the intended outcome, current scope, material
   exclusions, planned actions, and validation. Do not replace an adequate current plan or replan
   routine implementation details.
3. Inspect enough repository and domain context to verify the target, controlling cause, affected
   consumers, conventions, and material consequences.
4. Inspect repository state and follow the governing version-control rules before any VCS mutation.
   Preserve unrelated, pre-existing, user-authored, published, and uncertain work or history.
5. Resolve factual uncertainty directly. Ask only when an unresolved choice materially controls
   correctness, safety, compatibility, ownership, scope, or reversibility.

Stop before editing if the requested work conflicts with concurrent changes, depends on unavailable
authority, or cannot be bounded without modifying protected work.

## Concern Loop

Implement one independently reviewable concern at a time. Keep code, tests, documentation,
configuration, and migrations together when they are necessary to make that concern complete.

For each concern:

1. **Place the work** according to the version-control rules. Continue an existing task-owned
   concern only when the new work belongs to it; otherwise use separate task-owned history.
2. **Implement the smallest complete change** that achieves the intended outcome. Address the
   controlling cause when it is identifiable and in scope. Follow repository patterns and avoid
   speculative compatibility, abstraction, or adjacent cleanup. Do not weaken, omit, or reinterpret
   explicit constraints without authorization, or compromise correctness, safety, security, meaning,
   or intended effect to simplify the change.
3. **Verify proportionally** with the narrowest checks that provide meaningful evidence. Exercise
   the changed behavior and material failure modes, then expand checks when risk or coupling
   warrants it. Verification by the implementor is not formal diff review.
4. **Inspect the result** for unintended effects, missing consumers, incomplete supporting changes,
   stale artifacts, and inconsistencies. Account for affected users, related material, systems,
   workflows, persistent outputs and state, and other effects beyond the immediate files.
5. **Finalize the concern** only after focused verification passes. Follow the governing
   version-control rules to shape task-owned unpublished history into the fewest coherent, fully
   described revisions and leave a clean working state.
6. **Review the finalized concern** as a separate quality gate. Review every new or materially
   changed revision in dependency order, then the aggregate concern delta from its intended base.
   Check for behavioral regressions, safety and compatibility risks, missing validation, stale
   artifacts, and maintainability problems. Use the environment's independent review mechanism when
   available; an implementor's inspection or second pass is not independent review.
7. **Resolve applicable findings** as separate implementation work. Reverify and repeat only the
   finalization and review affected by the fix. Do not silently dismiss or defer a finding that
   blocks the intended outcome.

Complete this loop before beginning another independent concern. After all concerns are reviewed,
run any integration checks that genuinely required the complete task range and inspect the aggregate
task delta for cross-concern issues. Review the complete task range from its intended base. Resolve
applicable aggregate findings as implementation work, reverify and refinalize affected concerns,
repeat their reviews and any affected integration checks, and rerun the aggregate review. Do not
complete while applicable findings remain.

## Scope Changes And Blockers

- Revise and communicate the working plan when new evidence changes the intended outcome,
  boundaries, sequencing, or validation. Do not replan routine implementation details.
- Obtain explicit authorization before destructive, irreversible, externally visible, shared-system,
  or publication actions.
- If blocked, preserve a safe state and report what remains, why it is blocked, and what is needed
  to continue. Never present partial work as complete.

## Completion

Finish only when the authorized scope is implemented, focused verification and required integration
checks pass, each concern and the aggregate task range are finalized and independently reviewed,
applicable findings are resolved, and the repository is left in the state required by its
version-control rules.

Report the outcome, material changes, verification performed, checks skipped, blocked, or failed,
the review result, unresolved risks, and any material history transformations. Do not publish, push,
create a pull request, merge, or mutate an external system unless the user separately and explicitly
requests it.

## Boundaries

- Do not treat this skill as implementation authority.
- Do not create plans, task registries, progress files, approval records, or other persistent
  workflow state unless separately requested.
- Do not duplicate detailed VCS mechanics, commit-message procedures, or review criteria owned by
  the governing rules.
- Satisfy this skill's outcomes directly, using applicable specialized skills when available. Their
  absence must not prevent implementation when the required outcome can otherwise be achieved.
- Do not use this skill for a read-only review target.
- Do not include publication in implementation closeout.
