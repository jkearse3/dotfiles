---
name: implement
description: >-
  Carries an authorized repository change through implementation, verification, finalization, and
  review. Use for coding, configuration, documentation, tests, migrations, or review-fix edits; not
  for read-only work, planning without execution, publication, or external-system operations.
argument-hint: "<authorized repository change>"
---

# Implement

Complete an authorized repository change as coherent, verified, finalized, and
reviewed local history without creating persistent workflow state.

## Input

```text
$ARGUMENTS
```

Use the arguments, user request, and any current ready plan as the boundary. A
plan does not itself authorize changes. Unless the user narrows the outcome,
implementation authority includes creating and rewriting local, unpublished,
task-owned history needed to complete the request.

## Flow

1. **Align** on the complete outcome, scope, constraints, and validation. Stop
   for user direction when a material decision cannot be resolved from available
   evidence.
2. **Inspect** the repository, current behavior, affected consumers,
   conventions, and version-control state. Preserve unrelated and protected
   work.
3. **Implement** the next coherent revision of the requested change using the
   smallest complete approach that satisfies its part of the outcome.
4. **Verify** that revision with focused checks and inspect its complete diff
   for unintended or missing effects.
5. **Finalize** it as coherent, fully described local history with a clean
   working state.
6. **Review** the finalized revision before building dependent work on top of
   it. Use a fresh agent or context whenever available so implementation
   reasoning does not bias the review. Otherwise perform a separate review pass
   in the current context and disclose that fallback.
7. **Resolve findings** in the revision that introduced them when its
   unpublished history is safe to rewrite. Reverify, refinalize, and review
   until no applicable revision findings remain.
8. **Continue** the revision loop until the complete authorized request is
   implemented. Never build dependent work on an unreviewed revision.
9. **Validate and review the aggregate** finalized change. Place findings in the
   revision that introduced them when clear, reverify affected descendants, and
   repeat affected review. Create a new revision only for a genuinely separate
   concern.
10. **Complete** when the requested outcome is satisfied, required checks pass,
    no applicable findings remain, and the working state is clean. Report the
    result, verification, review outcome, history produced, skipped checks,
    fallback review context, and residual risks.

## Boundaries

- Do not treat investigation, explanation, proposals, planning, or review-only
  requests as implementation authority.
- Do not rewrite published, unrelated, pre-existing, user-authored, or uncertain
  history without explicit authority.
- Do not publish, push, merge, release, or mutate external systems.
- Do not create persistent plans, task registries, approval records, or workflow
  state.
- If blocked, preserve a safe state and report what remains, why, and what is
  needed.
