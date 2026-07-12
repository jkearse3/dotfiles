# Schema

New contracts use this shape. `Spec`, `Boundaries`, `Acceptance Criteria`, and `Validation` are
mandatory. Include Context, Research, or Implementation Approach only when their noted durable
information is relevant. The top-level fields before sections are `Status:` and `Bookmark:`.

```markdown
# Branch Contract

Status: active
Bookmark: <current-bookmark>

<!-- Include Context only when it preserves relevant durable intent or background. -->
## Context

### User Intent

<What the user asked for, in durable terms. Preserve important wording.>

### Background

<Why this bookmark exists, what prompted the work, and who or what behavior it affects.>

### Repo Facts

- `<path>`, `<symbol or section>`: <observed fact and why it matters.>

### Existing Behavior

<What the current checkout does before the agreed work is complete.>

### Desired Behavior

<What should be true when the agreement is satisfied.>

## Spec

<Short statement of the agreement this bookmark is trying to satisfy.>

## Boundaries

### In Scope

- <Repo areas and behavior this contract may change.>

### Out Of Scope

- <Explicit non-goals.>

### Allowed Implementation Changes

- <Types of code, config, test, or documentation changes allowed.>

### Forbidden Changes

- <Changes future agents must not make while satisfying this contract.>

### Stop Before

- <Decisions, risk, or ambiguity that require user direction.>

<!-- Include Research only when durable findings or decisions matter. -->
## Research

### Findings

- `<path>`, `<symbol or section>`: <fact discovered and why it matters.>

### Decisions

No decisions recorded.

### Questions

No open questions.

### Assumptions

No assumptions recorded.

<!-- Include Implementation Approach only when safe implementation needs durable guidance. -->
## Implementation Approach

### Strategy

<Expected approach and sequencing constraints. This is guidance, not an implementation log; amend it
if the agreed approach changes.>

### Likely Touch Points

- `<path>`: <why this file or area matters.>

### Design Constraints

- <Constraint future agents must preserve.>

### Non-Obvious Details

- <Detail future agents should not have to rediscover.>

## Acceptance Criteria

1. [ ] <Verifiable statement about the current checkout.>
   Check: <Cheap command or inspection that can verify this AC.>
   Evidence: Pending.

## Validation

- <Repo-level checks expected before marking the contract complete, when not already covered by AC
  `Check:` lines.>
- <Manual inspections when commands are insufficient.>
```

Valid statuses are:

- `active`: at least one non-superseded AC remains unsatisfied or partial, and no unresolved blocker
  prevents progress.
- `blocked`: a user decision, missing prerequisite, or unsafe ambiguity prevents progress.
- `complete`: every non-superseded AC is satisfied by the current checkout, with evidence.

Acceptance criteria use stable numbers. Never renumber ACs. Add new ACs after the highest existing
number.

AC markers mean:

- `[ ]`: not satisfied by the current checkout.
- `[x]`: satisfied by the current checkout; the declared `Check:` passed and `Evidence:` records its
  exact result or inspected fact.
- `[~]`: partially satisfied or externally/manual-satisfied as far as the agent can verify;
  `Evidence:` states what is present, what remains, or what external/manual confirmation is needed.
- `[!]`: blocked; `Evidence:` names the blocker or user decision needed.
- `[-]`: superseded; keep the old number and explain the replacement or reason in `Evidence:`.

Each AC must include a marker, a verifiable statement, a required `Check:` line, and a required
`Evidence:` line. `Check:` is planned proof, not observed evidence. `Evidence:` is the only durable
per-AC status note and must be the last AC body field. Write ACs as independently verifiable
outcomes, not implementation tasks. An AC does not have to be independently implementable: one
coherent implementation slice may advance multiple ACs, and one AC may require multiple coherent
slices.

Run the declared `Check:` exactly when it is safe and feasible. Evidence must identify the command
and result, or the inspected path, symbol, section, and observed fact. A failed declared check can
never produce `[x]`; use `[ ]`, `[~]`, or `[!]` according to the observed state. Do not substitute a
different check by interpretation. Changing an inadequate check is an approval-gated amendment.

The contract does not store a `## Next Slice` section, task queue, or implementation-log state.
Instead, keep the mandatory sections and any necessary conditional sections sufficient for a fresh
implementation agent to propose a reviewable next slice from the current measured state.

AC coverage must consider happy paths, negative or error paths, edge cases, existing behavior that
must keep working, repo conventions, tests, formatting, docs, and operational effects when those are
relevant to the agreement. Do not add boilerplate ACs for irrelevant categories, but do record why a
category matters when omission would make future interpretation ambiguous.

When recording repo facts, prefer stable anchors such as file paths, section names, function names,
config keys, command names, and quoted behavior. Line numbers may be included as draft-time
breadcrumbs, but they are not authoritative and must be refreshed or ignored when code drifts. Do
not bind contract validity to a specific commit or revision; reconcile against the current checkout.
