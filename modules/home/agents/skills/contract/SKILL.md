---
name: contract
description: >-
  Branch/bookmark contracts for the current jj bookmark. Use only for creating, loading, amending,
  or reconciling verifiable acceptance criteria for the current jj bookmark; not for general product
  specs, test specs, design docs, or implementation work.
argument-hint: "[intent or amendment]"
---

# Contract

Maintain a branch contract for the current jj bookmark. A branch contract is durable local state for
what this bookmark is trying to satisfy, what is in and out of scope, and how the current checkout
measures against that agreement.

The contract is a current agreement, not an implementation log. Current code is authoritative for AC
status. Revision IDs and earlier notes are advisory only.

The Markdown contract is the only durable contract state. Do not create additional durable state,
queues, or workflow-control files for this skill.

## Arguments

```
$ARGUMENTS
```

- Empty: load and reconcile the contract for the current bookmark.
- Non-empty with no current bookmark contract: draft a new contract from the user's intent.
- Non-empty with an existing current bookmark contract: treat the request as an amendment or
  clarification, not implementation work.
- Never treat arguments as permission to edit repository implementation files.

## Routing

1. Resolve the repository, current bookmark, and contract path using Local State.
2. If arguments are empty and the current bookmark contract exists, follow Reconcile.
3. If arguments are empty and no contract exists, ask what contract to draft and stop.
4. If arguments are non-empty and no contract exists, follow Create.
5. If arguments are non-empty and the contract exists, follow Amend.

## Local State

Resolve the jj root, exactly one current bookmark, bookmark slug, and Markdown contract path before
reading or writing a contract. Stop if the root cannot be resolved, the current bookmark cannot be
resolved, more than one current bookmark is reported, or the bookmark slug is empty.

A branch contract belongs to exactly one current jj bookmark and has one local file:

```text
<jj-root>/.agent/contracts/<bookmark-slug>.md
```

Build `<bookmark-slug>` from the current bookmark by replacing every character outside
`A-Za-z0-9._-` with `-`, collapsing repeated `-`, and trimming leading or trailing `-`. Stop if the
result is empty. Stop for user direction if the derived Markdown path collides with an existing
contract for a different `Bookmark:` value.

Do not create multi-bookmark or stack contracts.

Contract files are untracked local state. Do not add them to Git or jj, and do not create tracked or
exported snapshots.

Keep the human agreement and measured state in the Markdown contract. Do not move `Status:`, AC
markers, `Check:`, `Evidence:`, current-state notes, next-step guidance, research decisions,
questions, assumptions, or boundaries into another file. Do not create additional workflow-control
files or queues.

Before creating a contract file:

1. Create `<jj-root>/.agent/contracts/` if needed.
2. Ensure repo-local ignore or exclude state covers the whole contracts directory:

   ```text
   /.agent/contracts/
   ```

   In this git-backed setup, prefer `<jj-root>/.git/info/exclude` so the ignore rules stay local.

3. Verify the target contract path is ignored before writing it.

Stop for user direction if the ignore or exclude rule cannot be written, if the target path cannot
be verified as ignored, or if the repository uses a different local-ignore mechanism that is
unclear.

## Schema

New contracts use this shape. The top-level fields before sections are `Status:` and `Bookmark:`.

```markdown
# Branch Contract

Status: active
Bookmark: <current-bookmark>

## Context

<Why this bookmark exists, what prompted the work, who or what behavior it affects, and what
future agents must understand before interpreting the agreement.>

## Spec

<Short statement of the agreement this bookmark is trying to satisfy.>

## Boundaries

- In scope: <repo areas and behavior this contract may change.>
- Out of scope: <explicit non-goals.>
- Stop before: <decisions, risk, or ambiguity that require user direction.>

## Research

### Decisions

No decisions recorded.

### Questions

No open questions.

### Assumptions

No assumptions recorded.

## Acceptance Criteria

1. [ ] <Verifiable statement about the current checkout.>
   Check: <Cheap command or inspection that can verify this AC.>
   Evidence: Pending.

## Current State

<What the current checkout already satisfies, partially satisfies, or lacks.>

## Next Slice

<Next implementation slice using the pattern in Next Slice Guidance, or no pending slice.>
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
- `[x]`: satisfied by the current checkout; `Evidence:` names the inspection or check.
- `[~]`: partially satisfied; `Evidence:` states what is present and what remains.
- `[!]`: blocked; `Evidence:` names the blocker or user decision needed.
- `[-]`: superseded; keep the old number and explain the replacement or reason in `Evidence:`.

Each AC must include a marker, a verifiable statement, a `Check:` line, and an `Evidence:` line.
Write ACs as independently verifiable outcomes, not implementation tasks. An AC does not have to be
independently implementable: one coherent implementation slice may advance multiple ACs, and one AC
may require multiple coherent slices.

## Contract Readiness

Contract creation and amendment are discovery-first and consensus-seeking. Do not request approval
to write a contract until the agent and user agree there are no approval-relevant holes in the
branch agreement.

Before approval, pressure-test the agreement from multiple angles:

- Intended behavior, affected users or agents, and explicit non-goals.
- Existing behavior, compatibility expectations, and current-state facts.
- Edge cases, negative cases, failure modes, and recovery behavior.
- Data, configuration, persistence, security, privacy, and trust-boundary implications.
- User-visible behavior, developer-facing behavior, docs, tests, and operational effects.
- Boundaries, stop-before conditions, assumptions, decisions, and open questions.
- AC coverage, AC wording, and whether every `Check:` proves the AC without interpretation.
- The first `## Next Slice` and whether it can advance ACs without guessing agreement details.

Resolve uncertainty using the narrowest sufficient method. Inspect repo facts, patterns, tests,
docs, and current behavior directly when the answer is discoverable. Ask the user when the answer is
a decision. Prefer sequential questions when each answer may change which question or concern should
be raised next; batch only independent questions.

Treat these as approval blockers: vague ACs, vague or infeasible `Check:` lines, unclear boundaries,
missing edge cases, unsafe assumptions, unresolved user decisions, ambiguous current-state claims,
or a `## Next Slice` that requires future agents to infer contract intent.

Normal implementation unknowns may remain only when they can be resolved safely inside the approved
boundaries without changing ACs, checks, stop-before conditions, or user-visible behavior. Record
them as assumptions if future agents need to know they exist.

## Create

Use this path when arguments are non-empty and no contract exists for the current bookmark.

1. Resolve Local State.
2. Ensure `.agent/contracts/` exists and local ignore or exclude state covers `/.agent/contracts/`.
   Verify the target contract path is ignored locally before writing it.
3. Run Contract Readiness. Inspect enough repository facts to draft detailed context, boundaries,
   ACs, current-state notes, and checks. Do not edit implementation files.
4. If approval-relevant holes remain, ask the next question or present the unresolved concern and
   stop before writing the contract file. Continue this loop until the agent and user agree the
   branch agreement has no approval-relevant holes.
5. Draft a contract from the user intent, resolved decisions, and current repo facts.
6. Include detailed context, concrete boundaries, research decisions/questions/assumptions,
   verifiable ACs, current-state notes, and an implementation-ready `## Next Slice`.
7. Present the full draft and ask for explicit user approval before writing the contract file.
8. After approval, write only the contract file.

Creation must not edit repository implementation files, workflow state files, skill source, commits,
revision descriptions, bookmarks, or branches.

## Load

Use this path when the user asks to inspect the current contract without reconciling it.

1. Resolve Local State.
2. Read the current bookmark contract.
3. Stop if the contract `Bookmark:` value does not match the current bookmark.
4. Summarize the agreement, current measured status, unsatisfied or blocked ACs, and
   `## Next Slice`.

Loading must not edit any files.

## Reconcile

Use this path when arguments are empty and the current bookmark contract exists.

Reconciliation is an inline, idempotent measurement pass over the current checkout. It compares the
current checkout to the existing Markdown contract and updates only measured Markdown state.

1. Resolve Local State.
2. Read the Markdown contract fresh.
3. Stop if the contract `Bookmark:` value does not match the current bookmark. Do not guess or
   rebind the contract.
4. Treat `## Acceptance Criteria`, `## Boundaries`, and `Check:` lines as authoritative.
5. Inspect the current checkout against every non-superseded AC. Superseded ACs use the `[-]` marker
   and keep their existing evidence.
6. Run cheap relevant `Check:` commands when feasible. Skip checks that are expensive, unsafe,
   require unavailable secrets, or need user setup. Record the limitation in `Evidence:` instead of
   guessing.
7. Update measured Markdown state only: AC markers, `Evidence:` lines, `Status:`,
   `## Current State`, `## Next Slice`, and directly verified research question or assumption
   status.
8. Do not change agreement fields: `## Context`, `## Spec`, `## Boundaries`, AC wording, `Check:`
   lines, or research decisions. If the agreement is wrong or incomplete, report that amendment is
   needed.
9. If no measured Markdown changes are needed, leave the contract unchanged and report that
   reconciliation found no measured updates.

Reconciliation must reflect current code truth. It may mark an AC satisfied when the current
checkout already satisfies it, even if the satisfying change predates the contract or was moved into
a parent revision. It must not require a hard `Base` or `Compare` field. Do not use
unique-vs-inherited ownership detection while reconciling the contract.

Reconciliation must not edit repository implementation files, skill source, workflow state files,
commits, revision descriptions, bookmarks, or branches.

## Amend

Use this path when arguments are non-empty and a contract exists, or when reconciliation shows the
agreement itself is wrong, incomplete, or stale.

Amendment changes the agreement. Reconciliation measures code against the existing agreement. Keep
that distinction explicit.

During reconciliation, update only measured state: AC markers, evidence, status, current-state
notes, next-step guidance, and directly verified research question or assumption status.

Amendment may update `## Context`, `## Spec`, `## Boundaries`, AC wording, research decisions, or
add and supersede ACs. It requires explicit user approval before writing.

Before approval, run Contract Readiness against the amended agreement. If approval-relevant holes
remain, ask the next question or present the unresolved concern and stop before writing. Do not ask
for amendment approval until the agent and user agree the amended contract has no approval-relevant
holes.

After approval, write only the contract file. Do not edit repository implementation files, workflow
state files, skill source, commits, revision descriptions, bookmarks, or branches while amending.

Rules for AC changes:

- Never renumber ACs.
- If an AC already has evidence or likely related work, supersede it with `[-]` and add a
  replacement AC with a new number.
- Tiny wording clarifications may edit an AC in place only when the meaning does not change.
- Do not silently rewrite `## Context`, `## Spec`, `## Boundaries`, AC wording, or existing
  decisions during reconciliation. Propose an amendment instead.

## Next Slice Guidance

Keep `## Next Slice` useful as a manual implementation handoff into the `iterate` skill.
`## Next Slice` describes the next implementation slice; it is not permission for this skill to make
inline repository implementation edits.

When work remains, `## Next Slice` names the largest sensible implementation-ready slice that
advances one or more unsatisfied or partial ACs while remaining atomic. Prefer completing a coherent
AC or related set of ACs in one slice when that can be verified together without crossing a boundary
that needs a user decision, agreement change, or unrelated behavior change. Slice by the largest
verifiable AC movement that still has one clear purpose, not by estimated size, file count, task
count, or the smallest possible change.

Use this pattern:

```markdown
Make the largest coherent atomic change that advances the next unsatisfied acceptance criteria.

Target AC: <number or numbers>

Do this by <specific implementation boundary>.

Stop before <nearest ambiguity, unrelated behavior, or agreement change>.

Verify with <cheap check or inspection>.
```

The slice should include:

- Target AC numbers.
- A specific implementation boundary.
- The nearest stop-before condition.
- A cheap verification path.

Do not add size labels, time estimates, task queues, or mechanical file-by-file checklists. If the
largest AC movement is too broad to hand off coherently or cannot remain atomic, narrow
`## Next Slice` to the largest coherent part and make the stop-before condition explicit.

When no implementation work remains, say that no implementation slice is pending and identify the
next useful reconciliation or user-decision step.

Describe handoffs as user intents, not literal command examples. A typical manual loop is: reconcile
the branch contract, use `iterate` to take the next slice from the current branch contract, then
reconcile the branch contract again.

The contract skill does not write workflow state files, coordinate implementation work, commit,
describe, split, squash, switch bookmarks or branches, push, or move work between revisions.
