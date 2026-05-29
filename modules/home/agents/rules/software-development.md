# Software Development

Rules for planning, writing, and reviewing code.

## Philosophy

- Minimal solutions; no speculative abstraction.
- Evidence-based flexibility; add when needed.
- Short cycles: step → verify → repeat.
- Root cause over symptom; generic fix over bespoke patch.

## Destructive Operations

- Ask before deleting code you don't understand.
- Ensure restorability before deleting files or content.

## Language Rules

Invoke the `language-<lang>` skill if available (e.g. `language-go` for Go) when editing or
reviewing.

## Code Quality Checklist

Apply when planning, writing, or reviewing:

- **Design**: separation of concerns; right-sized abstractions (not over/under-engineered); minimal
  dependencies, correct direction; patterns consistent with the codebase; trust boundaries
  respected; narrowest visibility (nothing public without an external caller).
- **Correctness**: all error paths handled; inputs validated/sanitized; edge cases (empty, null,
  boundary); concurrency (races, deadlocks).
- **Clarity**: naming clear and consistent; nesting flattened.
- **Testing**: key paths covered; tests focused, not overlapping.

## Implementation

- Incremental; each iteration compiles/works.
- Follow existing patterns and libraries when sensible.
- Self-review against the checklist; iterate until it passes.

## Style

- Comments explain "why", not "what" — except a "what" comment for a complex logic block. Only when
  needed for understanding; no dividers, banners, or section markers.
- Full sentences with punctuation. Document all struct/object fields; no naked fields.
- Early returns; happy path at the left margin.

## File Organization

1. Main/exported components first; public APIs before implementation.
2. Private types/functions: after their single caller, or at the bottom if multiple callers.

## Blockers

- Architectural mismatch or API incompatibility requiring redesign.
- Multiple failed approaches with no clear path forward.
