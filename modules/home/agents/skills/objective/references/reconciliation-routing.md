# Reconciliation Routing

Caller-parsed reconciliation result contract and routing table.

## Reconciliation Result Contract

`briefs/phase-reconcile.md` returns this caller-consumed block. Callers must preserve top-level
status token matching, field order, and field meanings exactly.

```text
## Result: Reconciliation Summary

### Top-Level Status
- <NO_ACTION|NEEDS_USER_INPUT|NEEDS_IMPLEMENTATION|NEEDS_RESEARCH|NEEDS_DECISION|SPEC_CHANGE_REQUIRED>

### Dispositions
- [itemized feedback disposition list]

### Phase File Updates
- [issues, tasks, or continuation written; or "None"]

### Concerns
- [any issue requiring user input, or "None"]
```

Status routes:

- `NO_ACTION` — return to review approval.
- `NEEDS_IMPLEMENTATION` — return to implementation.
- `NEEDS_USER_INPUT` — stop and surface concerns to the user.
- `NEEDS_RESEARCH` — run `procedures/investigate.md`.
- `NEEDS_DECISION` — run `procedures/interrogate.md` for `Scope: objective`.
- `SPEC_CHANGE_REQUIRED` — run `procedures/spec.md`, then resume phase iteration at Step 3 (scope
  announcement).
