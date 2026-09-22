---
name: scratchpad
description: >-
  Maintains one worktree-local scratchpad per independent workstream as
  informal, durable working memory that remains usable by a fresh agent after
  context loss.
argument-hint: "[new <objective> | resume <scratchpad>]"
---

# Scratchpad

Externalize the working state that would otherwise be costly or error-prone to
reconstruct after losing conversation context. A scratchpad is informal working
memory, not a plan, report, transcript, activity log, or durable knowledge base.

At any reasonable checkpoint, a fresh agent given only the scratchpad and its
workspace should be able to continue without repeating substantial reasoning or
investigation. Optimize the scratchpad for that recovery outcome, not for a
fixed format.

## Start Or Resume

Use one scratchpad for one independent workstream in one worktree or workspace.
Concurrent agents use separate scratchpads, even when contributing to the same
larger objective. A serially resumed workstream continues using its existing
scratchpad.

For new work:

1. Identify the root of the current worktree or workspace. Do not redirect a
   linked worktree to its repository's primary checkout.
2. Choose a short lowercase kebab-case slug describing the objective.
3. Run
   `scripts/prepare-path.sh --workspace <absolute-worktree-or-workspace> <slug>`.
   Invoke the script by its path; it is independent of the current working
   directory. It safely creates the ignored local store, reserves a unique
   `YYYY-MM-DD-HHMMSS-<slug>.md` path, and prints its absolute path.
4. Begin using that one path and retain the association in working context. Do
   not create an active-scratchpad pointer or registry.

For resumed work, resolve an exact filename or path with
`scripts/resolve-scratchpad.sh --workspace <absolute-worktree-or-workspace> <exact-filename-or-path>`.
With no identifier, the resolver lists valid scratchpads in that workspace.
Infer candidates from the stated objective, filename wording, relevant
conversation context, and—when needed—the minimum orienting content from
plausible files. Never choose by timestamp, mtime, listing order, or assumed
recency. If no candidate is clearly intended or several remain plausible after
that inspection, ask the user rather than guessing.

Read the selected scratchpad before substantive action. Inspect the workspace
for changes that may have invalidated it: the workspace remains authoritative
about current files, while the scratchpad represents remembered working state.

## Work Freely

Use whatever form helps with the work: rough notes, partial checklists,
hypotheses, open questions, discoveries, constraints, decision rationale, failed
approaches, useful command or test outcomes, immediate intent, or reminders. No
heading or template is required.

Keep the scratchpad:

- informal but understandable to a fresh agent with no conversation history;
- concise enough to reread frequently;
- current about the objective, direction, relevant state, and next useful
  action;
- clear about what is established, what is inferred, and what remains uncertain;
- faithful to consequential user constraints and decision rationale;
- focused on details that would be expensive, difficult, or error-prone to
  reconstruct.

Do not copy large source fragments or command output, duplicate facts that are
trivial to rediscover, or polish the file into a status report. Do not record
credentials, tokens, private keys, `.env` values, or other secrets; name a safe
retrieval method instead.

## Keep It Recoverable

Update after meaningful state changes and before continuing when:

- a discovery changes the working understanding;
- a decision constrains later work;
- an attempt fails in a way worth avoiding;
- the plan or immediate intent changes;
- verification produces consequential evidence; or
- several details now need to remain jointly in mind.

Do not write after every routine action. Revise, reorganize, and prune freely so
stale notes do not compete with current state. The scratchpad may be messy; it
must not be misleading.

After context compaction, reread the already-associated scratchpad before
continuing. Do not depend on a pre-compaction hook: continuous maintenance
should make context loss uneventful.

## Transfer Or Finish

A scratchpad is local to its worktree or workspace. When a workstream is
explicitly transferred elsewhere, create a scratchpad in the destination,
transfer the useful current state, and stop updating the source copy. Never
assume separate copies remain synchronized.

Before concluding the workstream, preserve any consequential final state and
verification result. Leave the scratchpad in place unless the user requests
cleanup. Promote information that should outlive the workstream into its proper
durable owner—code, tests, project documentation, agent instructions, an issue,
or a persistent note—instead of treating the scratchpad as project history.

## Boundaries

- Write only within `.agent/scratchpads/` for scratchpad maintenance and safe
  creation of that ignored store.
- Keep the entire store ignored and untracked. Never stage or commit its
  contents.
- Never read or modify another workstream's scratchpad except to inspect the
  minimum orienting content needed to identify an explicitly requested
  resumption, or when explicitly resuming or transferring it.
- Start a new scratchpad when the objective materially changes; do not mix
  unrelated work because it occurs in one agent session.
- Do not use a scratchpad as execution authority, user approval, a formal plan,
  or a source of truth for repository state.
- Do not require agent-specific session IDs, lifecycle hooks, background
  processes, or runtime-specific metadata.

Maintainer validation lives at `tests/scratchpad-scripts.sh`. Run it when this
skill or its helper scripts change, not during ordinary scratchpad use.
