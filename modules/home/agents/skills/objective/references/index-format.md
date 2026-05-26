# Index File Format

Annotated specimen for `00-main.md`, the objective index.

## References

- `references/phases.md` — § Phase Sections for per-phase content.
- `references/templates.md` — phase-file template and creation rules.

`00-main.md` carries Context, Research, Acceptance Criteria, Approach, and the Phases index. Phase
content lives in separate files (see Phase Sections and Templates).

```markdown
## Context

Why this objective exists. Background and motivation.

## Research

Investigation findings, decisions, and questions.

Source attribution uses sub-bullets with prefixes:
- `src:` for web URLs and documentation references
- `ref:` for file paths and line numbers

Attribution is mandatory for findings, encouraged for questions and assumptions.

### Findings
- What was discovered with source/evidence
  - src: https://example.com/docs/relevant-page
  - ref: `path/to/file.ext:42` — what's relevant

### Decisions
- Choice made and rationale

### Questions
- [ ] Unresolved question
  - src: source that prompted this, if applicable

### Assumptions
- [ ] Unvalidated assumption
  - ref: `path/to/file.ext:10` — what informed this

## Acceptance Criteria

1. [ ] Clear, verifiable condition
2. [ ] Another condition (human)
3. [~] Implemented, awaiting validation
   - Query uses cursor-based pagination
   - Load test pending
4. [x] Validated criterion
   - `src/export.ts:38` writes RFC 4180 compliant output
   - User confirmed: tested via curl without token, got 401

An AC states a desired end state or behavior of the finished system — what is true once the work is done. It is never an implementation detail, a task, or a step toward that state.

Each AC should be independently verifiable. Split ACs that describe multiple distinct outcomes. Merge ACs that can't be verified independently of each other.

**Precision rules** — each AC must:
- **Declare a state or behavior, not a step** — "Export endpoint rejects unauthenticated requests with 401" not "Add an auth check to the export endpoint"
- **State what happens, not what doesn't** — "Names exceeding max truncate with ellipsis" not "doesn't break layout"
- **Include concrete values** — thresholds, formats, specific outputs. "Wraps at 80 chars" not "handles long text"
- **Describe observable outcomes, not qualities** — "Streams via cursor pagination" not "handles gracefully"

## Approach

Implementation roadmap. Must be detailed enough for autonomous iteration — an agent should be able to scope phases and execute without further user guidance.

Include: sequencing constraints, architectural decisions, key patterns to follow, and anything that would otherwise require asking the user mid-implementation.

## Phases

1. [x] [Selection Fix](./01-phase-1.md)
2. [ ] [Add Delete](./02-phase-2.md) *
3. [-] ~~Cancelled Thing~~
```
