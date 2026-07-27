# Phase Task Format

Task list format, annotations, and markers shared by phase subagent briefs.

## Task Format

```markdown
### Tasks

1. [ ] Task description
2. [ ] Another task (AC1, satisfy)
3. [ ] Write test for feature (AC1, codify)
4. [ ] Fix race condition (I1)
```

Tasks are a flat numbered list. No groupings or sub-headers.

## Task Annotations

- `(ACN, satisfy)` — implement behavior for ACN.
- `(ACN, enhance)` — improve or refine an already-satisfied ACN.
- `(ACN, codify)` — write test that verifies ACN.
- `(IN)` — address issue N.

## Task Markers

| Marker | Meaning  |
| ------ | -------- |
| `[ ]`  | Pending  |
| `[x]`  | Complete |
| `[!]`  | Blocked  |
