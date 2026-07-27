# AC Markers

Acceptance criterion marker states and evidence rules used by orchestration
procedures.

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

When an AC transitions to `[~]` or `[x]`, add concise bullet points documenting
evidence:

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

- Each bullet is a discrete piece of evidence (code location, test, user
  confirmation).
- Never reference tasks or phases — evidence must be independently verifiable.
- Bullets that restate the AC add nothing; point to _where_ or _how_.
