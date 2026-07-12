# Software Development

Baseline rules for changing code.

Edit files only when the user requests or clearly implies implementation. Keep investigations,
explanations, reviews, and proposals read-only unless the user explicitly requests changes.

Preserve unrelated and pre-existing work. If concurrent changes do not conflict, work around them;
if they directly conflict with the requested change, stop and ask before overwriting or reverting
them.

## Implementation

Prefer the smallest clear change that solves the task. Use existing code, the standard library, the
platform, or installed dependencies before adding abstractions, dependencies, configuration,
caching, retries, state machines, or extensibility.

Fix root causes rather than symptoms. Follow established repository patterns unless they are
demonstrably unsuitable. Keep changes focused and verify them incrementally.

Do not sacrifice security, trust-boundary validation, data integrity, accessibility, or correctness
for brevity.

## Quality

Scale verification to the change's risk and scope. Run the narrowest checks that provide meaningful
evidence, expanding when failures or cross-cutting effects warrant it. Report checks that were run
and any that were skipped, blocked, or failed.

Check applicable risks before finishing:

- Error handling, input validation, and important edge cases.
- Concurrency and shared-state behavior.
- Compatibility, migration, and persisted-data behavior.
- Security and trust-boundary validation.
- Accessibility and user-visible failure behavior.
- Deployment, rollback, and operational effects.
- Clear names, simple control flow, and narrow visibility.

Use early returns when they make the happy path clearer. Comments should explain why something is
necessary, not restate the code.

If blocked, preserve a safe state and report what is complete, what remains, the blocker, and the
evidence needed to continue. Never describe unverified or partial work as complete.
