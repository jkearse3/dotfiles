# Software Development

Baseline rules for changing code.

## Implementation

Prefer the smallest clear change that solves the task. Use existing code, the standard library, the
platform, or installed dependencies before adding abstractions, dependencies, configuration,
caching, retries, state machines, or extensibility.

Fix root causes rather than symptoms. Follow established repository patterns unless they are
demonstrably unsuitable. Keep changes focused and verify them incrementally.

Do not sacrifice security, trust-boundary validation, data integrity, accessibility, or correctness
for brevity.

## Quality

Before finishing, run focused verification and check applicable risks:

- Error handling, input validation, and important edge cases.
- Concurrency and shared-state behavior.
- Clear names, simple control flow, and narrow visibility.

Use early returns when they make the happy path clearer. Comments should explain why something is
necessary, not restate the code.
