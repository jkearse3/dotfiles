---
name: contract
description: >-
  Branch/bookmark contracts for the current jj bookmark. Use only for creating, loading, amending,
  reconciling, proposing, or autonomously iterating toward verifiable acceptance criteria for the
  current jj bookmark; not for general product specs, test specs, or design docs.
argument-hint: "[iterate [once] | intent or amendment]"
---

# Contract

Maintain the bookmark-bound agreement and measured acceptance state for the current jj bookmark.
Contract operations exclude broad product discovery and cross-session context transport. Only the
explicit `iterate` operation may implement the agreement; applicable implementation and
version-control rules govern all resulting repository and revision lifecycle behavior.

The contract is a current agreement, not an implementation log. Current code is authoritative for AC
status. Revision IDs and earlier notes are advisory only. The contract should still preserve durable
implementation-relevant context: agreed approach, relevant files, constraints, non-obvious repo
facts, and validation strategy. Do not record chronological progress except where it changes current
measured state.

The Markdown contract is the only durable contract state. Do not create additional durable state,
queues, or workflow-control files.

## Arguments

```
$ARGUMENTS
```

- Empty: reconcile the contract for the current bookmark when one exists.
- `iterate`: autonomously implement coherent revisions until the contract is complete or blocked.
- `iterate once`: complete at most one coherent revision, reconcile, and stop.
- Non-empty with no current bookmark contract: draft a new contract from the user's intent.
- Non-empty with an existing current bookmark contract: treat the request as an amendment or
  clarification unless the intent clearly asks to load/show/status/inspect or propose, derive,
  refresh, or update the next slice.
- Never infer implementation authority from arguments other than the explicit iterate operations.

## Runbook

1. When the request clearly intends to create a new contract, confirm whether it should use the
   current bookmark or a new bookmark before resolving the contract path. If bookmark placement must
   change, stop and require that placement to be completed outside this operation before continuing.
2. Resolve the repository, current bookmark, and contract path using `references/local-state.md`.
3. If local state cannot be resolved, stop with the exact blocker.
4. If the current bookmark contract exists, read it before routing and stop if its `Bookmark:` value
   does not match the current bookmark.
5. If the arguments explicitly request `iterate` or `iterate once`, follow `procedures/iterate.md`.
6. If the user clearly asks to propose, derive, refresh, or update the next slice, follow
   `procedures/propose-slice.md`.
7. If the user clearly asks to load, show, inspect, or report contract status, follow
   `procedures/load.md`.
8. If arguments are empty and the current bookmark contract exists, follow
   `procedures/reconcile.md`.
9. If arguments are empty and no contract exists, ask what contract to draft and stop.
10. If arguments are non-empty and no contract exists, follow `procedures/create.md`.
11. If arguments are non-empty and the contract exists, follow `procedures/amend.md`.

Do not reinterpret one operation as another. Loading and proposing are read-only. Creation and
amendment change the agreement only after explicit approval. Reconciliation may change measured
contract state without changing the agreement. Iteration may change implementation and local VCS
state under its procedure, but must not change the agreement without amendment approval.

## Procedure Imports

Before following a procedure, read only that procedure and the reference files it names. Treat those
files as imported instructions for the selected operation; do not preload files needed only by later
procedures.

Shared references:

- `references/local-state.md`: repository, bookmark, slug, contract path, local-ignore, and
  no-extra-state rules.
- `references/schema.md`: contract schema, statuses, AC marker meanings, and measured-state rules.
- `references/readiness.md`: creation and amendment readiness checks and approval blockers.
- `references/slice-selection.md`: lazy next-slice proposal guidance.
- `references/iteration.md`: autonomous slice, pivot, and contract-specific stop rules.

Procedures:

- `procedures/create.md`: create a new contract after approval.
- `procedures/load.md`: read and summarize the current contract without edits.
- `procedures/reconcile.md`: measure the current source of truth against the contract.
- `procedures/amend.md`: change the agreement after approval.
- `procedures/propose-slice.md`: propose a next implementation slice without editing the contract.
- `procedures/iterate.md`: apply the applicable implementation lifecycle until the contract
  terminates.
