# Contracts

Shared instructions for objective procedures, briefs, and references.

## File Conventions

Use this structure where applicable:

1. `# Name`
2. One-sentence purpose.
3. `## Arguments` for user-provided arguments or flags.
4. `## References` for imported instructions.
5. `## Steps` for ordered execution.
6. `## Contracts` for exact outputs, write boundaries, gates, and invariants.

`## References` are normative. Before executing a file, read every listed reference. Follow named
sections from references instead of restating them locally.

## Shared Operations

### Slugify

Lowercase; replace `/` and whitespace with `-`; strip non-alphanumeric characters except `-`.

Collapsing whitespace to `-` is intentional, aligning with `references/structure.md` ("hyphens for
spaces"). Slug inputs are jj bookmark names, which rarely contain whitespace, so the practical
effect is negligible.

### Extract Objective Slug

Strip `YYYY-MM-DD-HHMM-`; if absent, strip `YYYY-MM-DD-`.

### Load Current Objective

Resolve `.objectives/_current` to the active objective directory, then read `00-main.md`.

Stop with this nudge if no valid objective is active:

```text
No active objective. Want me to load or create one?
```

### Load Phase Subagent State

Read the phase state file provided by the orchestrator and load the sections the caller needs:

- `### Context` — phase intent and any delegated context.
- `### Approach` — strategy, constraints, and implementation patterns.
- `### Tasks` — work items and AC/task annotations.
- `### Issues` — existing issues for follow-up or deduplication.
- `### Continuation` — read-only resume context from a routed follow-up, if present.

Use `### Continuation` only to understand why the subagent resumed. Do not create, update, clear, or
route continuation; lifecycle decisions remain with the orchestrating procedure.

Read `.objectives/_current/00-main.md` `## Acceptance Criteria` for AC text used by later
brief-specific assessment or validation steps.

### Phase Iterate Result Blocks

`procedures/phase-iterate.md --auto-commit` returns one of these caller-consumed blocks. Callers
must preserve token matching, field order, and field meanings exactly.

Incomplete result:

```text
PHASE_INCOMPLETE
phase: <N>
reason: <blocked_tasks|unresolved_issues|implement_concerns>
details: <specific blockers or concerns>
```

Meanings:

- `PHASE_INCOMPLETE` — phase iteration stopped before commit because user-visible follow-up is
  required.
- `phase` — focused phase number.
- `reason` — machine-readable stop category; keep values limited to the listed tokens.
- `details` — human-readable blockers, unresolved issues, or implementation concerns.

Complete result:

```text
PHASE_COMPLETE
phase: <N>
commit_message: <the full revision description used>
ac_status: <list of AC number and new status, e.g. "AC1: [~], AC3: [~]">
```

Meanings:

- `PHASE_COMPLETE` — phase changes were committed and the phase index was marked complete.
- `phase` — completed phase number.
- `commit_message` — exact full revision description passed to `jj commit -m`.
- `ac_status` — latest AC status snapshot captured by phase iteration for targeted ACs.

### Reconciliation Result Contract

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

- `NO_ACTION` — return to Step 8 approval.
- `NEEDS_IMPLEMENTATION` — return to Step 4 implementation.
- `NEEDS_USER_INPUT` — stop and surface concerns to the user.
- `NEEDS_RESEARCH` — run `procedures/investigate.md`.
- `NEEDS_DECISION` — run `procedures/interrogate.md` for `Scope: objective`, or
  `procedures/phase-interrogate.md` for `Scope: phase`.
- `SPEC_CHANGE_REQUIRED` — run `procedures/spec.md`, then resume phase iteration at Step 3.

### Spike Auto-Creation

When no active objective exists, callers may create a spike objective by providing:

- Spike kind: e.g. `research spike` or `decision spike`.
- Require-topic nudge: exact stop text when no topic argument was provided.
- Slug example: exact topic-to-slug example to show the derivation style.
- Confirmation example: exact prompt text to present with the derived slug.
- Create argument: the confirmed slug passed to `procedures/create.md`.

Apply the flow:

1. Require topic. If no topic argument was provided, emit the require-topic nudge and stop.
2. Extract slug. From the topic, take 2-3 key terms forming a compact, descriptive slug (lowercase,
   hyphen-separated). Drop filler words. Follow the caller's slug example.
3. Confirm with user. Present the derived slug using the caller's confirmation example and accept an
   override.
4. Create branch + objective. Read and follow `procedures/create.md` with the confirmed slug as the
   argument. This creates the bookmark and objective and loads it.
5. Continue. The topic argument carries through to the caller's topic-derivation step with no
   re-derivation needed.

### Continuation Lifecycle

Apply this operation after a routed action has persisted its declared result:

1. Inspect the focused phase `### Continuation`.
2. If the continuation status matches the completed route and the result makes the next resume point
   unambiguous, remove `### Continuation` or replace it with the next required route.
3. If the next resume point is still ambiguous, update `### Continuation` with a precise Status,
   Source, Route, Summary, Clear when, and any needed Payload. Do not clear it.
4. Never clear or update continuation before the routed action's declared result write is complete.

When a phase-local route discovers that objective-level follow-up is required, update
`### Continuation` to the appropriate objective-level route only after the phase-local result is
persisted. The routed objective-level procedure owns any later `00-main.md` write.

## Invariants

- Preserve exact result tokens and strings consumed by callers.
- Preserve approval gates; do not turn user-approved steps into automatic writes.
- Subagents may write only what their brief's `## Write Permissions` section declares; anything not
  listed is denied.
- Preserve AC numbering and marker semantics.
- Preserve phase numbering and focus semantics.
- Preserve the single-revision invariant: no `jj commit`, `jj new`, or `jj split` inside
  implement/verify loops; the orchestrator owns revision lifecycle.
- Persist phase-local continuation before any procedure stops or routes away because unresolved
  phase-local follow-up cannot be completed in the current path.
- Clear phase-local continuation per `references/contracts.md` § Continuation Lifecycle.
