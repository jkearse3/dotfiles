---
name: contract
description: >-
  Branch/bookmark contracts for the current jj bookmark. Use only for creating,
  reading, amending, or reconciling an ordered milestone agreement; not for
  implementation, general product specs, test specs, or design docs.
argument-hint: "[reconcile | status | creation or amendment intent]"
---

# Contract

Maintain the bookmark-bound agreement and measured acceptance state for the
current jj bookmark. Contract operations exclude broad product discovery,
implementation planning, implementation, and cross-session context transport.

The contract is a current agreement, not an implementation log or workflow
engine. Its milestones are an ordered sequence of accepted outcomes. Each
milestone owns the acceptance criteria that prove its outcome. Document order is
the only sequencing rule.

The Markdown contract is the only durable contract state. AC markers and
evidence are the only measured state. Derive milestone and contract state
whenever needed; never persist summaries, queues, selections, readiness, or
revision maps.

## Arguments

```
$ARGUMENTS
```

- Empty or `reconcile`: lazily reconcile the ordered contract against the
  current checkout.
- A reconciliation request with a target, scope, or mode is unsupported. Do not
  discard its arguments or reinterpret it as ordinary reconciliation; explain
  that `reconcile` now performs the single ordered pass and ask whether to
  proceed.
- `status`, loading, showing, or inspection intent: report recorded state
  without running checks.
- Creation intent with no current bookmark contract: draft a new contract.
- Amendment intent with an existing contract: draft the agreement change for
  approval.
- Never interpret a contract request as implementation authority. When
  implementation is requested, explain that reconciliation produces the
  acceptance gap consumed by planning or execution.

## Runbook

1. Resolve the repository, current bookmark, and contract path using
   `references/local-state.md`.
2. If local state cannot be resolved, stop with the exact blocker.
3. If the current bookmark contract exists, read it before routing and stop if
   its `Bookmark:` value does not match the current bookmark.
4. If no contract exists, report it and stop for status, loading,
   reconciliation, or amendment requests. For clear creation intent, follow
   `procedures/create.md`; for an empty or ambiguous request, ask what contract
   to draft and stop.
5. If the contract does not satisfy the current schema, report the exact defects
   and stop. Do not infer, migrate, or preserve behavior from another schema.
6. If arguments are empty or request reconciliation, follow
   `procedures/reconcile.md`. Reconciliation has no selectable scope or mode.
   Stop for confirmation first when the request includes one.
7. If the user requests status, loading, showing, inspection, or reporting
   without measurement, follow `procedures/load.md`.
8. If the user clearly asks to change the existing agreement, follow
   `procedures/amend.md`.
9. Otherwise, ask whether the user intends reconciliation, status, or amendment
   and stop.

Do not reinterpret one operation as another. Loading is read-only. Creation and
amendment change the agreement only after explicit approval. Reconciliation
changes measured state without changing the agreement. No operation edits
implementation or version-control state.

## Procedure Imports

Before following a procedure, read only that procedure and the reference files
it names. Treat those files as imported instructions for the selected operation;
do not preload files needed only by later procedures.

Shared references:

- `references/local-state.md`: repository, bookmark, contract path,
  local-ignore, and no-extra-state rules.
- `references/schema.md`: ordered milestone schema, derived states, AC markers,
  and evidence rules.
- `references/template.md`: contract shape loaded only during creation.
- `references/readiness.md`: creation and amendment readiness checks and
  approval blockers.

Procedures:

- `procedures/create.md`: create a new milestone contract after approval.
- `procedures/load.md`: derive and summarize the current contract without edits.
- `procedures/reconcile.md`: lazily measure milestones in document order until
  the first gap.
- `procedures/amend.md`: change the milestone agreement after approval.
