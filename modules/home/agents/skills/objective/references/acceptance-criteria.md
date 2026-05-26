# Acceptance Criteria

AC marker states, validation evidence, stability rules, and termination conditions.

## References

- `references/index-format.md` — precision rules that govern how to phrase an AC.

An AC is a desired end state or behavior of the finished system — not a task or implementation step.
See `references/index-format.md` for the precision rules that govern how to phrase one.

## AC States

| Marker | Meaning                                     |
| ------ | ------------------------------------------- |
| `[ ]`  | Not started                                 |
| `[~]`  | Implemented, awaiting human validation      |
| `[x]`  | Validated (code verified or human approved) |
| `[!]`  | Regressed                                   |
| `[-]`  | Invalidated or superseded                   |

- ACs marked `(human)` require user sign-off.
- Verify validates ACs by inspecting code, not just running tests.
- Tests are supporting evidence, not the sole source of truth.

## AC Validation Evidence

When an AC transitions to `[~]` or `[x]`, add concise bullet points documenting evidence:

```markdown
1. [x] Export produces valid CSV
   - `src/export.ts:38` writes RFC 4180 compliant output
   - `export.test.ts:12` covers empty, single-row, and unicode cases
2. [x] Auth required for export endpoint (human)
   - User confirmed: tested via curl without token, got 401
3. [~] Pagination supports 10k+ rows
   - Query uses cursor-based pagination
   - Load test pending
```

Rules:

- Each bullet is a discrete piece of evidence (code location, test, user confirmation)
- Never reference tasks or phases — evidence must be independently verifiable
- Bullets that restate the AC add nothing; point to _where_ or _how_

## AC Stability

**Stable numbering**: AC numbers are stable — never renumber, gaps are fine. Tasks reference ACs via
`(ACN, satisfy/codify/enhance)`, so renumbering breaks all existing references.

**Mutability boundary**: An AC is **locked** when either:

- Its marker is not `[ ]` (work has been done: `[~]`, `[x]`, `[!]`)
- Any task references it via `(ACN, satisfy)`, `(ACN, codify)`, or `(ACN, enhance)` in any phase

Unlocked ACs (`[ ]` with no task references) can be updated in place. Locked ACs must be
invalidated.

**Invalidation format** (reuses `[-]` + strikethrough pattern from phases):

```markdown
2. [-] ~~Offset-based pagination supports 10k+ rows~~ (superseded by AC5)
   - Was [~] with cursor implementation pending
5. [ ] Cursor-based pagination supports 10k+ rows (supersedes AC2)
```

Rules:

- `[-]` marker + strikethrough text + `(superseded by ACN)` or `(invalidated: reason)`
- Evidence bullets on invalidated ACs preserved — documents what was done
- New AC adds `(supersedes ACN)` annotation
- `[-]` ACs excluded from completion check (like `[-]` phases)
- Task references to invalidated ACs remain valid — text is preserved via strikethrough

## Termination

Phase complete when: All phase tasks `[x]` + all phase issues resolved

Objective complete when: All active ACs `[x]` in `00-main.md` + all phases complete (`[-]` ACs
excluded)
