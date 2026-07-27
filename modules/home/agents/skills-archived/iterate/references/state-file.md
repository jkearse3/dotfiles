# State File

## Invariants

- State path is always `<jj-root>/.agent/iterate.md`.
- `## Acceptance Criteria` and `## Boundaries` are authoritative.
- `## Context` explains why the iteration exists and why ACs matter.
- `## Research` stores findings, decisions, questions, and assumptions that
  shape work.
- `## Tasks` is mutation scratch, scoped just-in-time and tied to ACs or verify
  issues when applicable.
- Each AC has a fixed body: statement, required `Check:`, optional `Details:`,
  then required `Evidence:` last. `Check:` is the planned proof method,
  `Details:` holds AC-local supporting list items, and `Evidence:` is
  verify-owned observed proof.
- AC markers and evidence are verify-owned. Implement may record candidate
  verification notes in tasks or research, but must not mark ACs checked or
  write AC `Evidence:` lines.
- `## Issues` is verify-owned for normal issue lifecycle: blockers, findings,
  regressions, and unsafe assumptions. Implement addresses issues with `(IN)`
  tasks and records only direct blockers needed for user input, safety, or
  boundaries.

## State File Setup

Resolve the workspace with `jj root`. If it fails, stop: this skill expects a jj
workspace.

State file:

```text
<jj-root>/.agent/iterate.md
```

Before creating or updating the state file, ensure `<jj-root>/.agent/` has an
untracked `.gitignore` with these narrow rules. Establish it only after the
current operation has authority to write the state file and before that
operation's first write:

```gitignore
/.gitignore
/iterate.md
```

Create the directory and file when absent. If `.agent/.gitignore` already
exists, inspect it and proceed only when its contents and ownership are
compatible and it does not hide unrelated `.agent` contents; never overwrite it.
Existing shared Git exclude entries may remain but are not sufficient.

Make jj snapshot the working copy and use `jj status` and targeted
`jj file list` output to confirm the local `.gitignore` and an existing state
file are absent from the snapshot. When no state file exists, create and verify
an empty `.agent/iterate.md` probe instead, then remove it before creating the
real state file. If either path is already tracked, verification would require
untracking an existing path, or setup cannot be safely verified, stop before
writing and ask for direction. Remove only the probe created by this procedure;
do not discard pre-existing content.

Before a new state file, run `jj st`. If it lists changes, stop and ask whether
they belong in this iteration or should be handled first. Existing changes are
fine when resuming an active state file.

## Planning Draft Review

State-file creation and edits follow host approval rules. Approval to create or
edit the state file does not approve activation.

Use Planning Draft Review when the persisted state is useful as a shared
planning artifact but is not ready for activation approval. Reread
`.agent/iterate.md` from disk, present the relevant draft state or full file
contents needed for review, identify unresolved planning gaps, and stop without
asking for activation approval.

## Persisted Plan Approval

Use Persisted Plan Approval only after readiness passes and no approval-relevant
uncertainty remains.

Activation requires explicit user approval of the exact full `.agent/iterate.md`
contents most recently shown in chat. To request activation approval, reread
`.agent/iterate.md` from disk, present the entire file contents in chat, ask for
approval of that exact persisted file, and stop.

Approval to activate the exact persisted plan authorizes routine execution
within that plan until it completes, blocks, fails, or changes scope. This
includes in-bound implement and verify work, routine `.agent/iterate.md`
progress updates, in-scope repo edits allowed by `## Boundaries`, and
verification commands listed or implied by AC `Check:` lines.

Activation approval does not authorize scope changes, out-of-bound work,
continuing after a failed or blocked plan, destructive or hard-to-reverse
changes not named by the plan, external service mutations, user-visible system
configuration changes, or VCS lifecycle actions not included in the approved
plan or finalization candidate.

## State File Schema

Create new state files with exactly these sections. Leave `## Tasks` empty until
implement scopes work just-in-time from ACs, issues, context, research, and repo
inspection.

```markdown
# Iterate

Status: planning
Next: planning

## Context

[Why this iteration exists, what prompted it, and why the ACs below matter.]

## Research

### Findings

### Decisions

### Questions

### Assumptions

## Acceptance Criteria

1. [ ] <observable behavior or repo state>
   Check: <feasible inspection, command, or manual confirmation path that proves this AC>
   Details:
   - <optional AC-local supporting detail; omit `Details:` when unused>
   Evidence: Pending.

## Approach

[Small mutation strategy.]

## Boundaries

- Iteration-specific limits for edits, inspection, workflow actions, and stop-before conditions. If
  scope is discoverable, state the repo relationship that makes discovered files or behavior in scope.

## Tasks

## Issues

No open issues.
```

## Acceptance Criterion Body

Every AC uses fixed body ordering:

- Statement line with the stable AC number, marker, and observable criterion.
- Required `Check:` line describing the planned proof method for the AC.
- Optional `Details:` block for AC-local supporting list items.
- Required `Evidence:` line recording verify-owned observed proof for the
  current checkout.

`Evidence:` is always the last body item under the AC. If the AC needs bullets,
examples, caveats, or other supporting content, put them under `Details:` so
they do not interleave with verify-owned evidence. `Check:` is planning-owned
proof intent; it is not observed evidence.

## State Machine

Required control fields:

```text
Status: planning | active | blocked | review | complete | finalized
Next: planning | implement | verify | review | finalize | none
```

Allowed control-field pairs:

- `Status: planning`, `Next: planning`
- `Status: active`, `Next: implement`
- `Status: active`, `Next: verify`
- `Status: review`, `Next: review`
- `Status: complete`, `Next: finalize`
- `Status: blocked`, `Next: none`
- `Status: finalized`, `Next: none`

Block: set `Status: blocked`, set `Next: none`, record a concrete `[!]` blocker,
and stop.

## Finalization Candidate

Verify may add `## Finalization Candidate` only after every non-invalidated AC
has evidence and no open issues remain. When repository changes exist, verify
must propose `closeout: finalize-revision` unless the user explicitly requested
no VCS closeout. When no repository changes exist, or when the user explicitly
requested no VCS closeout, use `closeout: none`.

Adding or replacing `## Finalization Candidate` is a non-mutating state-file
proposal. It does not authorize `jj describe`, `jj new`, `jj commit`, push,
split, squash, or any other VCS lifecycle action. The current candidate must be
displayed and explicitly approved for closeout before finalization runs; review
may combine that approval with work acceptance. Plans and boundaries may
prohibit VCS lifecycle execution without prohibiting a proposed revision
description or finalization candidate.

If present, the section must contain `closeout` and only the fields required by
that closeout mode.

For no VCS lifecycle closeout:

```markdown
## Finalization Candidate

closeout: none
```

For describing the current `@` and then creating a fresh working-copy revision:

````markdown
## Finalization Candidate

closeout: finalize-revision

target_commit: <current @ commit id>

revision_description:
```text
<complete proposed jj revision description>
```
````

No other finalization-candidate metadata is allowed. Replace the whole section
when writing a fresh candidate, and remove it when verification does not pass.

## Markers

Markers for ACs, tasks, and issues:

- `[ ]` pending, open, or not yet checked.
- `[x]` complete or checked.
- `[~]` satisfied as far as the agent can tell, but external/manual confirmation
  is required.
- `[!]` blocked, failed, regressed, or unsafe to continue without input.
- `[-]` invalidated or superseded; excluded from completion checks.

For ACs, the marker belongs only on the statement line. `Check:`, `Details:`,
and `Evidence:` are body fields, not independently marked work items.

## AC Stability

AC numbers are stable. Never renumber ACs; gaps are fine.

An AC is locked when either condition is true:

- Its marker is not `[ ]`.
- Any task references it via `(ACN, satisfy)`, `(ACN, codify)`, or
  `(ACN, enhance)`.

Unlocked ACs may be updated in place. Locked ACs must not be rewritten silently.
If new information weakens, contradicts, supersedes, narrows, or makes evidence
stale for a locked AC, block for user direction or invalidate the old AC with
`[-]` and add a new AC.

Invalidation format:

```markdown
2. [-] ~~Old behavior remains true~~ (superseded by AC5)
   Check: Previous proof method remains documented for auditability.
   Evidence: Previous evidence remains preserved.
5. [ ] New behavior replaces the old behavior. (supersedes AC2)
   Check: Inspect the replacement behavior.
   Evidence: Pending.
```

Preserve evidence on invalidated ACs and keep it last. Evidence on retained ACs
must still match their wording. Verify examines every non-invalidated AC, not
just ACs touched by the latest task.

## Task Traceability

Tasks are a flat numbered list. Implement creates or refines them just-in-time
after reading the state file and inspecting the repo.

Task annotations:

- `(ACN, satisfy)` implements behavior for ACN.
- `(ACN, codify)` adds or updates checks for ACN.
- `(ACN, enhance)` improves or refines already-satisfied ACN behavior.
- `(IN)` addresses issue N.

Task completion does not complete the iteration. Verify-owned AC evidence
completes agent verification; human acceptance or explicit closure completes the
iteration.
