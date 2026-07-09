---
name: contract
description: >-
  Branch/bookmark contracts for the current jj bookmark. Use only for creating, loading, amending,
  reconciling, or deriving the next slice for verifiable acceptance criteria for the current jj
  bookmark; not for general product specs, test specs, design docs, or implementation work.
argument-hint: "[intent or amendment]"
---

# Contract

Maintain a branch contract for the current jj bookmark. A branch contract is durable local state for
what this bookmark is trying to satisfy, what is in and out of scope, and how the current checkout
measures against that agreement.

The contract is a current agreement, not an implementation log. Current code is authoritative for AC
status. Revision IDs and earlier notes are advisory only. The contract should still preserve durable
implementation-relevant context: agreed approach, relevant files, constraints, non-obvious repo
facts, and validation strategy. Do not record chronological progress except where it changes current
measured state.

The Markdown contract is the only durable contract state. Do not create additional durable state,
queues, or workflow-control files for this skill.

## Arguments

```
$ARGUMENTS
```

- Empty: load and reconcile the contract for the current bookmark when one exists.
- Non-empty with no current bookmark contract: draft a new contract from the user's intent.
- Non-empty with an existing current bookmark contract: treat the request as an amendment or
  clarification unless the intent clearly asks to load/show/status/inspect or derive/refresh the
  next slice.
- Never treat arguments as permission to edit repository implementation files.

## Runbook

1. Resolve the repository, current bookmark, and contract path using `references/local-state.md`.
2. If local state cannot be resolved, stop with the exact blocker.
3. If the current bookmark contract exists, read it before routing and stop if its `Bookmark:` value
   does not match the current bookmark.
4. If the user clearly asks to derive, refresh, or update the next slice, follow
   `procedures/derive-next-slice.md`.
5. If the user clearly asks to load, show, inspect, or report contract status, follow
   `procedures/load.md`.
6. If arguments are empty and the current bookmark contract exists, follow
   `procedures/reconcile.md`.
7. If arguments are empty and no contract exists, ask what contract to draft and stop.
8. If arguments are non-empty and no contract exists, follow `procedures/create.md`.
9. If arguments are non-empty and the contract exists, follow `procedures/amend.md`.

## Procedure Imports

Before following a procedure, read only that procedure and the reference files it names. Treat those
files as imported instructions for the selected operation; do not preload files needed only by later
procedures.

Shared references:

- `references/local-state.md`: repository, bookmark, slug, contract path, local-ignore, and
  no-extra-state rules.
- `references/schema.md`: contract schema, statuses, AC marker meanings, and measured-state rules.
- `references/readiness.md`: creation and amendment readiness checks and approval blockers.
- `references/next-slice.md`: `## Next Slice` derivation guidance.

Procedures:

- `procedures/create.md`: create a new contract after approval.
- `procedures/load.md`: read and summarize the current contract without edits.
- `procedures/reconcile.md`: measure the current source of truth against the contract.
- `procedures/amend.md`: change the agreement after approval.
- `procedures/derive-next-slice.md`: derive or refresh `## Next Slice` without implementation work.
