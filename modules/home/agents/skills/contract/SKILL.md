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

1. Resolve the repository, current bookmark, and contract paths using Local State.
2. If arguments are empty and the current bookmark contract exists, follow Reconcile.
3. If arguments are empty and no contract exists, ask what contract to draft and stop.
4. If arguments are non-empty and no contract exists, follow Create.
5. If arguments are non-empty and the contract exists, follow Amend.

## Local State

Resolve the jj root, exactly one current bookmark, bookmark slug, Markdown contract path, and
sidecar state path before reading or writing a contract. Use the bundled helper's `paths` mode for
this resolution. Stop if the helper reports that the root cannot be resolved, the current bookmark
cannot be resolved, more than one current bookmark is reported, or the bookmark slug is empty.

A branch contract belongs to exactly one current jj bookmark and has two local files:

```text
<jj-root>/.agent/contracts/<bookmark-slug>.md
<jj-root>/.agent/contracts/<bookmark-slug>.state.json
```

The Markdown file is the human-readable agreement and measured state. The JSON sidecar is only a
machine-maintained reconciliation cache signal.

The helper builds `<bookmark-slug>` from the current bookmark by replacing every character outside
`A-Za-z0-9._-` with `-`, collapsing repeated `-`, and trimming leading or trailing `-`. Stop for
user direction if the derived Markdown path collides with an existing contract for a different
`Bookmark:` value.

Do not create multi-bookmark or stack contracts.

Contract files and state files are untracked local state. Do not add them to Git or jj, and do not
create tracked or exported snapshots.

Keep the human agreement and measured state in the Markdown contract. Do not move `Status:`, AC
markers, `Check:`, `Evidence:`, current-state notes, next-step guidance, research decisions,
questions, assumptions, or boundaries into JSON. Do not create additional workflow-control files or
queues.

The sidecar JSON schema is limited to reconciliation cache metadata:

```json
{
  "contract_sha256": "<sha256-of-entire-markdown-contract>",
  "working_copy_commit_id": "<full-jj-commit-id-for-@>"
}
```

The JSON state must not store AC text, AC markers, evidence, current-state prose, next-step prose,
boundaries, research content, current bookmark names, bookmark target commit IDs, revision
descriptions, operation IDs, short commit IDs, or timestamps.

Before creating a contract file or writing a sidecar state file:

1. Create `<jj-root>/.agent/contracts/` if needed.
2. Ensure repo-local ignore or exclude state covers the whole contracts directory:

   ```text
   /.agent/contracts/
   ```

   In this git-backed setup, prefer `<jj-root>/.git/info/exclude` so the ignore rules stay local.

3. Verify target paths are ignored before writing them. For contract creation, verify the Markdown
   target before writing the contract. Before writing sidecar state, verify the contracts directory
   and the derived Markdown and JSON state targets are ignored.

Stop for user direction if the ignore or exclude rule cannot be written, if the target path cannot
be verified as ignored, or if the repository uses a different local-ignore mechanism that is
unclear.

## Schema

New contracts use this shape. The top-level fields before sections are `Status:` and `Bookmark:`.
Reconciliation cache metadata lives in the sidecar JSON state file.

```markdown
# Branch Contract

Status: active
Bookmark: <current-bookmark>

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

## Next

<Next implementation slice using the pattern in Next Guidance, or no pending implementation slice.>
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

## Bundled Scripts

The skill includes one helper at `scripts/state.py`, relative to the skill root. The helper is
internal to this skill, not a repo-global command and not installed on `PATH`. Its help output is
the source of truth for detailed usage.

The helper supports `paths`, `check`, and `write` modes. It derives the current contract and sidecar
state paths from the jj root and current bookmark, so these modes take no contract path argument.
`paths` prints the resolved jj root, current bookmark, bookmark slug, Markdown contract path, and
sidecar state path without requiring an existing contract file. `check` computes the current cache
inputs and compares them with the derived `.state.json` file. Fresh state means the sidecar has only
the two-field schema above and matches the same whole-contract hash plus the same jj working-copy
revision. It exits `0` for fresh state, exits `1` for safely stale state, and exits `2` for
diagnostics that require stopping. `write` writes the derived `.state.json` file from the final
Markdown contract and current jj working-copy revision after the caller has satisfied the current
path's write gate. It exits `0` when written and exits `2` for diagnostics.

The helper prints concise `key=value` output such as `bookmark=... contract_path=...`,
`status=fresh`, `status=stale reason=...`, or `status=written`. It uses the current bookmark name
only to derive the contract path and validate the Markdown `Bookmark:` field. It uses the whole
Markdown contract SHA-256 and the full jj `commit_id` for `@` to decide freshness. It does not use
the current bookmark target, jj `change_id`, short ID prefixes, timestamps, operation IDs, or
earlier notes to decide freshness.

The helper never prompts, switches bookmarks, edits Markdown contracts, runs AC checks, performs
reconciliation, installs anything, or mutates files other than the adjacent state JSON in `write`
mode.

## Create

Use this path when arguments are non-empty and no contract exists for the current bookmark.

1. Resolve Local State with the helper's `paths` mode.
2. Ensure `.agent/contracts/` exists and local ignore or exclude state covers `/.agent/contracts/`.
   Verify the target contract path is ignored locally before writing it.
3. Inspect the repository lightly to draft concrete boundaries and AC checks. Do not edit
   implementation files.
4. Draft a contract from the user intent and current repo facts.
5. Include concrete boundaries, research placeholders, verifiable ACs, current-state notes, and an
   implementation-ready `## Next`.
6. Present the draft and ask for explicit user approval before writing the contract file.
7. After approval, write only the contract file.

Creation must not edit repository implementation files, workflow state files, skill source, commits,
revision descriptions, bookmarks, or branches.

## Reconcile

Use this path when arguments are empty and the current bookmark contract exists.

Reconciliation is worker-only. Worker dispatch details live in `references/reconcile-dispatch.md`,
and the worker brief lives in `briefs/reconcile.md`.

1. Resolve Local State with the helper's `paths` mode.
2. Resolve absolute paths for the workspace root, Markdown contract, sidecar state, helper script,
   and reconciliation worker brief.
3. Dispatch a worker/subagent with those absolute paths and an instruction to read the brief
   directly from disk and follow it. Do not inline the brief contents, require named agents, or rely
   on host-specific command configuration.
4. If the host has no worker/subagent dispatch mechanism, stop with a diagnostic. Do not run the
   heavy reconciliation flow inline.
5. If the worker reports unavailable inputs, failed helper diagnostics, out-of-bounds changes,
   implementation edits, agreement changes, revision lifecycle actions, or any required user
   decision, stop with the diagnostic.
6. After the worker returns, treat its summary as advisory. Reread the Markdown contract and rerun
   the helper's `check` mode before reporting durable status, AC markers, current-state notes,
   next-step guidance, or remaining diagnostics.

The reconciliation worker may auto-apply bounded measured-state updates. It may directly edit only
measured contract state under `.agent/contracts/`: AC markers, `Evidence:` lines, `Status:`,
`## Current State`, `## Next`, directly verified research question or assumption status, and the
adjacent sidecar JSON state file. It must not satisfy contract ACs by editing repository
implementation files inline, and it must not change agreement fields such as `## Spec`,
`## Boundaries`, AC wording, `Check:` lines, or research decisions.

Reconciliation must reflect current code truth. It may mark an AC satisfied when the current
checkout already satisfies it, even if the satisfying change predates the contract or was moved into
a parent revision. It must not require a hard `Base` or `Compare` field. Do not use
unique-vs-inherited ownership detection while reconciling the contract.

## Amend

Use this path when arguments are non-empty and a contract exists, or when reconciliation shows the
agreement itself is wrong, incomplete, or stale.

Amendment changes the agreement. Reconciliation measures code against the existing agreement. Keep
that distinction explicit.

During reconciliation, update only measured state: AC markers, evidence, status, current-state
notes, next-step guidance, and directly verified research question or assumption status.

Amendment may update `## Spec`, `## Boundaries`, AC wording, research decisions, or add and
supersede ACs. It requires explicit user approval before writing.

After approval, write only the contract file. Do not edit repository implementation files, workflow
state files, skill source, commits, revision descriptions, bookmarks, or branches while amending.

Rules for AC changes:

- Never renumber ACs.
- If an AC already has evidence or likely related work, supersede it with `[-]` and add a
  replacement AC with a new number.
- Tiny wording clarifications may edit an AC in place only when the meaning does not change.
- Do not silently rewrite `## Spec`, `## Boundaries`, AC wording, or existing decisions during
  reconciliation. Propose an amendment instead.

## Next Guidance

Keep `## Next` useful as a manual implementation handoff without coupling this skill to a specific
workflow.

When work remains, `## Next` names the smallest coherent implementation-ready slice that advances
one or more unsatisfied or partial ACs without crossing a boundary that needs a user decision,
agreement change, or unrelated behavior change. Slice by the next verifiable AC movement, not by
estimated size, file count, or task count.

Use this pattern:

```markdown
Make the smallest coherent change that advances the next unsatisfied acceptance criteria.

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
next AC movement is too broad to hand off coherently, narrow `## Next` to the first coherent part
and make the stop-before condition explicit.

When no implementation work remains, say that no implementation slice is pending and identify the
next useful reconciliation or user-decision step.

Describe handoffs as user intents, not literal command examples. A typical manual loop is: reconcile
the branch contract, use the next slice from the current branch contract, then reconcile the branch
contract again.

The contract skill does not write workflow state files, coordinate implementation work, commit,
describe, split, squash, switch bookmarks or branches, push, or move work between revisions.
