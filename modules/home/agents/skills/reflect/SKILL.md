---
name: reflect
description: >-
  Reviews what the current session cost and proposes the smallest change to the
  current repository's agent instructions and skills that would have prevented
  it, preferring deletion over rewording and rewording over additions. Use when
  the user asks to reflect on, learn from, or retro the session, or to update
  repo rules or skills from it. Not for editing generated or installed
  instructions or guidance outside the repository, saving notes, or reviewing
  code.
---

# Reflect

Turn what went wrong or slowly in this session into the smallest change to the
current repository's agent guidance, so the next session in this repository goes
faster. Most sessions need no change; when nothing qualifies, say so and stop.

Guidance means the files this repository tracks that agents load as
instructions: `AGENTS.md` and `CLAUDE.md` files at any depth, the files they
include, and skill directories (a `SKILL.md` plus its supporting files). Edit
only those, and only inside the repository. Never edit generated or installed
copies such as `~/.claude`, `/nix/store` paths, or a host's auto-memory; they
are read-only or overwritten by their source.

Invoking this skill authorizes reading and proposing. The user's approval of a
proposal authorizes editing the approved files and finalizing them locally,
never publication.

## 1. Find Moments

List each moment in the session that cost something a future session in this
repository would pay again:

- the user corrected or redirected the agent;
- a command, approach, or assumption failed and was replaced;
- the agent spent several steps finding a fact about the repository, such as a
  command, a path, or a convention;
- the agent followed an instruction that was wrong, stale, or did not apply;
- a skill step misfired, was skipped, or had to be worked around.

For each, record what happened, what it cost, and what would have prevented it.
Drop moments caused by one-off conditions, such as a typo, a flaky network, or a
locked password manager, and lessons the session's own changes already captured,
such as a bug it fixed.

## 2. Trace Each Moment

Find the guidance text involved by searching the repository for it, and classify
the moment:

- **Caused.** Repository text caused it: fix that text.
- **Missed.** Repository text covered it, but the agent missed or misread it:
  tighten, move, or reword that text. Never restate it elsewhere.
- **Global.** No repository text is involved, and either the lesson is not
  specific to this repository, such as a general working practice, or the text
  involved exists only outside the repository, such as global rules seen only
  through an installed copy: report it as a global candidate and edit nothing.
- **Uncovered.** No text covered a lesson specific to this repository: a
  candidate addition.

A search that finds the text inside this repository makes it repository guidance
even when the agent loaded it from an installed copy; edit the repository
source.

## 3. Choose the Smallest Change

Prefer, in order: delete, tighten, update, add. For each moment, first ask
whether removing or shortening existing text would have prevented it. Text that
was wrong, stale, contradicted by the repository, or duplicated elsewhere is a
deletion candidate whether or not a moment points at it.

Propose an addition only when all of these hold:

- it would help a different future task in this repository, not only a rerun of
  this one;
- a session cannot learn it cheaply from the repository itself, such as from a
  `package.json` script, a `Makefile` target, or the code;
- no existing text covers it.

Put each addition in the narrowest file that loads when it is needed: a skill
over `AGENTS.md`, a nested `AGENTS.md` over the root one. Aim for a net line
count at or below zero across all proposals.

## 4. Get an Independent Check

When anything is proposed, give a fresh subagent the proposed diffs, the moment
each one answers, and the current contents of every file they touch, but not
this session's reasoning. Ask it to find a smaller alternative for each
proposal: a deletion or merge instead of an edit, an edit instead of an
addition, or no change. Weigh its answer against yours rather than adopting
either. If the host cannot start a fresh agent, do this pass yourself and say so
in the proposal.

## 5. Propose

Show one row per change, then the global candidates:

| Moment | File | Action | Net lines |
| ------ | ---- | ------ | --------- |

Show each change's diff below the table. Ask which changes to apply; the user
may approve a subset or edit them.

Under **Global candidates**, give each Global moment as a prompt in its own
fenced `text` block, for the user to paste into an agent working in the
repository that holds their global guidance. That agent has none of this
session's context, so each prompt states what happened and what it cost, the
lesson, the instruction text involved if any, and the suggested wording. It asks
the agent to find the guidance that covers the lesson, prefer deleting or
tightening existing text over adding new text, and propose the change before
making it. Leave out secrets, personal details, and anything about the current
repository the lesson does not need.

When nothing qualifies, report that no change is needed, list any global
candidates, and stop.

## 6. Apply

If the session's other work is still unfinalized in the working copy, ask the
user before editing. Fetch trunk from the remote. Then apply the approved
changes in two passes; in each, run the repository's formatter and any check
that covers the edited files, and finalize following `finalize-changes`:

1. Fold each change whose text an unmerged revision in the task's stack
   introduced: edit it in the working copy and finalize it into that revision.
   Fold nothing once the session's work has merged, even by squash or rebase,
   since those leave its original revisions in the stack after a fetch; ask the
   user when you cannot tell.
2. If changes remain, start an empty revision on trunk under a new task-owned
   branch or bookmark, make the remaining changes there against trunk's files,
   and finalize them as one revision whose only concern is the guidance change,
   so it lands independently of the session's work.

Write any revision description from the repository's point of view, without
mentioning the session or this skill.

Report the revision and branch or bookmark each change landed in, each applied
change, the checks run with their results, where the working copy ends, and the
global candidates.
