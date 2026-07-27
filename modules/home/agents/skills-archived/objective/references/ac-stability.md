# AC Stability

Acceptance-criterion locking and invalidation rules.

## AC Stability

**Stable numbering**: AC numbers are stable — never renumber, gaps are fine.
Tasks reference ACs via `(ACN, satisfy/codify/enhance)`, so renumbering breaks
all existing references.

**Mutability boundary**: An AC is **locked** when either:

- Its marker is not `[ ]` (work has been done: `[~]`, `[x]`, `[!]`).
- Any task references it via `(ACN, satisfy)`, `(ACN, codify)`, or
  `(ACN, enhance)` in any phase.

Unlocked ACs (`[ ]` with no task references) can be updated in place. Locked ACs
must be invalidated.

**Invalidation format** (reuses `[-]` + strikethrough pattern from phases). Keep
the invalidated and replacement criteria as separate lists so their stable
numbers remain literal Markdown:

```markdown
2. [-] ~~Offset-based pagination supports 10k+ rows~~ (superseded by AC5)
   - Was [~] with cursor implementation pending
```

```markdown
5. [ ] Cursor-based pagination supports 10k+ rows (supersedes AC2)
```

Rules:

- `[-]` marker + strikethrough text + `(superseded by ACN)` or
  `(invalidated: reason)`.
- Evidence bullets on invalidated ACs preserved — documents what was done.
- Evidence bullets on retained ACs must still match the retained wording. If new
  wording weakens, supersedes, or changes what old evidence proves, update the
  evidence or invalidate the AC before marking the AC set stable.
- New AC adds `(supersedes ACN)` annotation.
- `[-]` ACs excluded from completion check.
- Task references to invalidated ACs remain valid — text is preserved via
  strikethrough.
