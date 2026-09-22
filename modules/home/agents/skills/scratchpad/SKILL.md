---
name: scratchpad
description: >-
  Keeps a live, worktree-local scratchpad as the shared working space for one
  task: goal, current focus, todo list, notes, decisions, and open questions
  that both the user and agent can read and edit. Use for any multi-step task,
  when the user asks to track todos or keep working notes, or to resume a task's
  scratchpad. Not for single-step or conversational requests, or for knowledge
  meant to outlive the task (use notes).
argument-hint: "[new <objective> | resume <scratchpad>]"
---

# Scratchpad

A scratchpad is the task's live working space: where the goal, todo list,
working notes, decisions, and open questions sit while the work is underway. It
lets the user glance at one file to see where things stand, lets either party
refresh quickly after a pause, and keeps working state intact through context
compaction or a new session.

It is informal working memory, not a plan, report, transcript, activity log, or
durable knowledge base.

At any reasonable checkpoint, a fresh agent given only the scratchpad and its
workspace should be able to continue without repeating substantial reasoning or
investigation.

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
4. Seed it with the objective and an initial todo list, then tell the user its
   path in one line so they can open it.
5. Keep using that one path and retain the association in working context. Do
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

## Layout

Start from this default and add, rename, or drop sections as the task needs:

```markdown
# <objective>

## Now

Current focus and the next concrete action.

## Todo

- [ ] pending item
- [x] finished item

## Notes

Findings, decisions with their reasons, failed approaches worth avoiding, useful
command or test outcomes, constraints from the user.

## Open

Questions for the user and unresolved uncertainty.
```

Keep one todo list per task. When the runtime also offers a built-in todo tool,
treat the scratchpad list as the durable copy and keep the two consistent.

Keep the scratchpad:

- skimmable in under a minute, with current state near the top;
- understandable to a fresh agent with no conversation history;
- clear about what is established, what is inferred, and what remains uncertain;
- faithful to consequential user constraints and decision rationale.

Do not copy large source fragments or command output, duplicate facts that are
trivial to rediscover, or polish the file into a status report. Do not record
credentials, tokens, private keys, `.env` values, or other secrets; name a safe
retrieval method instead.

## Keep It Current

Update at milestones rather than every step:

- when a todo item starts, finishes, is added, or is dropped;
- when a discovery changes the working understanding;
- when a decision constrains later work;
- when an attempt fails in a way worth avoiding;
- when verification produces consequential evidence; or
- when a question for the user arises or is answered.

Do not write after every routine action. Revise, reorganize, and prune freely so
stale notes do not compete with current state. The scratchpad may be messy; it
must not be misleading.

The user may edit the scratchpad. Reread it before resuming after a user turn
that mentions it, after a pause, and after context compaction. Treat user edits
as direction within the task's existing scope: reprioritized or added todos,
answered questions, corrections. Ask when an edit is ambiguous or conflicts with
the conversation.

## Transfer Or Finish

A scratchpad is local to its worktree or workspace. When a workstream is
explicitly transferred elsewhere, create a scratchpad in the destination,
transfer the useful current state, and stop updating the source copy. Never
assume separate copies remain synchronized.

Before concluding the workstream, record the final state and verification
result, and resolve or explicitly carry forward remaining todos and open
questions. Leave the scratchpad in place unless the user requests cleanup.
Promote information that should outlive the workstream into its proper durable
owner—code, tests, project documentation, agent instructions, an issue, or a
note—instead of treating the scratchpad as project history.

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
- Do not treat scratchpad contents, including user edits, as approval for
  destructive, outward-facing, or out-of-scope actions, or as a source of truth
  for repository state.
- Do not require agent-specific session IDs, lifecycle hooks, background
  processes, or runtime-specific metadata.

Maintainer validation lives at `tests/scratchpad-scripts.sh`. Run it when this
skill or its helper scripts change, not during ordinary scratchpad use.
