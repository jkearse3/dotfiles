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

## AC Validation And Derivation

Use this operation when a verify brief decides whether phase changes satisfy objective ACs and
writes marker/evidence updates back to `00-main.md`.

Inputs:

- `## Acceptance Criteria` from `00-main.md`.
- Phase `### Tasks`, including `(ACN, satisfy)` and `(ACN, enhance)` annotations.
- Completed task context and changed code for the current phase.

Apply validation:

1. Identify relevant code from completed phase tasks and changed files.
2. Inspect the implementation directly; validate by reading code, not just by running tests.
3. Treat tests as supporting evidence. Cite existing tests when they cover the behavior.
4. Select the AC marker from § AC States based on observed satisfaction and confidence.
5. Record concise evidence per § AC Validation Evidence for every AC moved to `[~]` or `[x]`.

Apply derivation for ACs targeted by phase tasks:

1. If all references for an AC are `(ACN, enhance)`, preserve the existing marker, text,
   annotations, and evidence; enhancement work does not change satisfaction status by itself.
2. If the phase task carries a `(human)` annotation for the AC, preserve the AC marker, text, and
   `(human)` annotation. Do not replace human validation with code validation.
3. If a `(ACN, satisfy)` task references an AC that does not exist in `00-main.md`, flag a readiness
   issue in the phase file instead of creating an AC silently.
4. For matching `(ACN, satisfy)` tasks, derive the AC marker from validation and add evidence notes
   for `[~]` or `[x]` results.

Write `## Acceptance Criteria` in a single edit after derivation. Preserve existing AC text and
`(human)` annotations, update only derived markers and evidence notes for ACs assessed by the verify
brief, and include all derived AC statuses in the verify summary.

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

## AC Conflict Check

Use this operation before writing new objective ACs that were drafted from a topic-scoped spec
change or surfaced as objective AC candidates during phase interrogation.

Inputs:

- Existing `## Acceptance Criteria` from `00-main.md`.
- New AC candidates after caller-specific deduplication.
- Existing task references in any phase, used to determine whether an AC is locked.

Apply the lifecycle:

1. Scan each existing AC for contradiction, overlap, or supersession by a new candidate.
2. For unlocked ACs (`[ ]` and no task references `(ACN, ...)`), update the AC in place.
3. For locked ACs (marker is not `[ ]`, or task references exist), invalidate using the `[-]` +
   strikethrough + cross-reference format from § AC Stability.
4. Present the conflict analysis to the user: which ACs will be updated, which invalidated, and
   which new ACs will be added. If no conflicts exist, present the drafted ACs or candidates for
   approval.
5. Require user approval before any write to `## Acceptance Criteria`.
6. After approval, write all ACs to `## Acceptance Criteria`: existing ACs plus any
   updates/invalidations and new ACs numbered sequentially after the highest existing AC number.

## Termination

Phase complete when: All phase tasks `[x]` + all phase issues resolved

Objective complete when: All active ACs `[x]` in `00-main.md` + all phases complete (`[-]` ACs
excluded)
