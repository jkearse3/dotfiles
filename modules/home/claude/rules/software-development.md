# Software Development

Rules for all software development work: planning, writing, and reviewing code.

## Philosophy

- Minimal solutions; no speculative abstraction
- Evidence-based flexibility; add when needed
- Short cycles: step -> verify -> repeat
- Root cause over symptom; generic fix over bespoke patch

## Destructive Operations

- Preserve unknown code — ask before deleting code you don't understand
- Ensure restorability before deleting files or content

## Language Rules

When editing or reviewing code, invoke the `language-<lang>` skill if available (e.g., `language-go`
for Go files).

## Code Quality Checklist

Apply when planning, writing, OR reviewing code.

**Design & Architecture**

- Separation of concerns clear?
- Abstractions appropriate? over/under-engineered?
- Dependencies minimized? direction correct?
- Patterns consistent with codebase?
- Security - trust boundaries respected?
- Visibility narrowest? nothing public without an external caller?

**Correctness & Safety**

- Error handling - all paths covered?
- Inputs validated/sanitized?
- Edge cases - empty, null, boundary?
- Concurrency - race conditions? deadlocks?

**Clarity & Maintainability**

- Naming - intent clear? consistent?
- Nesting - can it be flattened?

**Testing**

- Key paths tested?
- Tests focused, not overlapping?

## Implementation

- Incremental; each iteration must compile/work
- Follow existing patterns and libraries when sensible
- Default to narrowest visibility; widen only when a caller outside the scope requires it
- Self-review against Code Quality Checklist; iterate until it passes

## Style

- Comments explain "why", not "what"
- Exception: "what" comments for complex logic blocks
- Only add comments if necessary for understanding; no dividers, banners, or section markers
- Use full sentences with punctuation
- Document all struct/object fields; no naked fields
- Early returns; happy path at left margin
- Public before private; locality for single-use

## File Organization

1. Main/exported components first
2. Public APIs before implementation
3. Private functions/types:
   - Single caller: immediately after
   - Multiple callers: at bottom

## Blockers (stop and ask)

- Architectural mismatch or API incompatibility requiring redesign
- Multiple failed approaches with no clear path forward
