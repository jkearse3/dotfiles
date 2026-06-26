# Software Development

Rules for planning, writing, and reviewing code.

## Minimality

Prefer the smallest clear change that solves the current task.

Before writing code, check whether the behavior can be handled by existing code, the standard
library, the platform, or an installed dependency. Do not add abstractions, dependencies,
configuration, caching, retries, state machines, or extensibility unless the current task proves
they are needed.

Fix root causes rather than symptoms. Do not trade away security, trust-boundary validation,
data-loss handling, accessibility, or correctness for brevity.

## Implementation

Work incrementally: inspect the relevant code, make a focused change, then verify it. Follow the
repo's existing patterns and libraries unless there is evidence they are wrong for this task.

When editing or reviewing language-specific code, invoke the matching `language-<lang>` skill if
available.

## Quality Checks

Before finishing, check the changed code for:

- Correct error handling, input validation, and important edge cases.
- Concurrency issues where shared state, async work, or parallel execution is involved.
- Clear names, simple control flow, and narrow visibility.
- Focused tests or verification for the behavior changed.

## Style

Use early returns to keep the happy path clear. Comments should explain why something is necessary,
not restate what the code does.
