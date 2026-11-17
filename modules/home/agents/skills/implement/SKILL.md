---
name: implement
description: >-
  Implements a requested change in a jj repository as finalized revisions: new
  ones, changes folded into existing ones, or both. Plans a roadmap of
  milestones, gives each milestone to one fresh implementer subagent that plans
  it from the code already landed and builds its changes while this session
  lands each one. Use when the user asks to implement, build, or carry out a
  change from any input: a request, issue, plan, note, or spec. To implement and
  then review in one go, use iterate. Not for fixing review findings (use
  diff-fix), read-only investigation or review, Git-only checkouts, or
  publication.
---

# Implement

Turn any description of a change into finalized, independently valid revisions
on the user's current branch. This session coordinates: it keeps the run record,
lands each change, and asks the user. Subagents plan, edit, and run checks; if
the host cannot start fresh agents, stop and report.

Plan coarsely across the whole task and in detail only for the next milestone,
from the code that has landed, so no detailed plan is written against code that
does not exist yet. One implementer plans and builds each milestone, so the
agent that explored the code is the one that changes it.

## Input

Take what to implement from the request and context, in whatever form it
arrives: the request itself, a file, an issue, a note, a plan, a spec, or the
conversation. Draw from it the outcome, explicit criteria, exclusions, settled
decisions, and binding requirements such as constraints and prescribed
implementation details, and preserve their wording. Read a referenced artifact
only as far as needed to hand it on; do not explore the codebase here. Treat the
input's settled decisions as user decisions.

## Outcomes

Hold these throughout the run, choosing the jj commands that achieve them. When
one cannot be held, that needs the user.

- **One branch.** The run works on the branch `@` sits on: the mutable ancestors
  of `@-` (`mutable() & ::@-`), plus the revisions the run adds. It starts only
  from an empty, undescribed `@` with one parent on a branch without merges or
  undescribed revisions; otherwise stop and say why. When the request names a
  revision off that branch, ask the user to check out its branch.
- **Valid history.** Every revision the run creates or changes holds one
  concern, is described as `finalize-changes`'
  `references/revision-descriptions.md` requires, and is valid on its own as
  `finalize-changes`' Sequencing section defines. A change lands in a new
  revision or in the existing revision whose concern it belongs to, and later
  revisions that use what it changed are updated to match.
- **Nothing else moves.** No revision off the branch changes, and no other
  workspace's working copy is rewritten or rebased. A fold or conflict
  resolution changes only revisions the user authored, pushed or not, or the
  request names.
- **A bookmark marks the tip.** Use a bookmark on `@`, or on `@-` when the
  branch has revisions, asking when more than one qualifies; otherwise create
  one. It always points at the branch's tip.
- **A clean working copy.** Between changes, whenever the user is asked, and at
  the end, `@` is an empty child of the tip and no unlanded attempt remains on
  the branch.
- **Resumable.** `run.md` holds enough to resume after compaction.

Before the first planner, run
`scripts/prepare-run.sh --workspace <workspace-root> <slug>` by its path, with
the workspace's absolute root and a slug of a few words for the outcome. It
prepares the ignored `.agent/implement/` store, reserves a new run directory,
and prints its absolute path; a jj `No matching entries` warning on stderr is
benign. On a non-zero status, stop and report its error; never fall back to the
scratchpad or the workspace. Never track, publish, or delete the store or the
run directory.

Invoking this skill authorizes writing the run directory; creating revisions on
the branch; rebasing its revisions, and changing and rewording those the user
authored or the request names; discarding attempts that did not land; creating
or moving the branch's bookmark. Besides the branch, the store, the run
directory, and the session scratchpad, it authorizes no other writes, external
changes, or publication.

## Run Record

`run.md` in the run directory is the source of truth: reread it, and the skill
its header names after `Then:`, after compaction or whenever memory and the file
could differ; after Report, continue with that skill's next step. Only this
session writes it, whenever its contents change; subagents read it. It holds:

- a header: the workspace path, the branch's base, the bookmark, the input's
  source, and, when the invoking skill asks for it, `Then:` with the skill whose
  step follows this one;
- `Input`: the outcome, criteria, exclusions, settled decisions, and binding
  requirements verbatim, or, for an input file under the `.agent/` directory
  that holds the run store, its path and which of its sections map to each;
- `Decisions`: each user answer, dated;
- `Roadmap`: the ordered milestones, each with its goal, the input criteria it
  completes, and its status: `pending`, or `done` with the revisions it created
  or changed;
- `Current milestone`: its planned changes, each `pending` or `landed` with the
  revision it created or changed and its check reports;
- `Outcome`, written at the end.

Throwaway files, such as description drafts and check logs, stay in the session
scratchpad.

## Loop

A planner, and an implementer while it plans, works read-only: no edits, VCS
mutation, scratch files in the repository, or delegation. Each gets the path of
`run.md` and `finalize-changes`' Sequencing section verbatim, and returns its
questions for the user and the defaults it chose instead of asking. Show the
user the defaults and ask the questions at once, record the answers, and send
them back to the agent that planned when they change its plan.

When something needs the user, ask, offering decide or stop. A decision goes to
the agent whose plan it changes: the milestone's implementer for the current
milestone, or a fresh planner for pending milestones or landed work, which
revises them to carry it out, for example by dropping a change and what depends
on it or by adding one that fixes landed work. A revision that drops or changes
an input criterion, settled decision, or binding requirement needs the user too.
Stop ends the run and goes to Report.

1. **Roadmap.** Dispatch a fresh planner to explore as far as the roadmap needs
   and return ordered milestones, and every user-owned decision the input leaves
   open across the task. A milestone is a coherent chunk of a few revisions that
   relies only on earlier milestones; a small task is one milestone. Write the
   roadmap, show it, and continue without waiting for approval.
2. **Plan the milestone.** For the earliest `pending` milestone, dispatch a
   fresh implementer with the path of `run.md` and the milestone. It first plans
   from the branch as it now stands and returns the milestone's changes in
   order. Each change has a goal, its targets, the checks that prove it, and
   where it lands: a new revision above a named revision, or a fold into a named
   revision, either of which may be an earlier change of this plan. Give each
   change one concern, and include the follow-up folds that keep later revisions
   valid. The implementer also returns evidence when a later milestone is wrong.
3. **Build and land** each change in order. Put a fresh working copy where the
   change belongs and send the change to the milestone's implementer. It follows
   `coding-style`, edits only the working copy, performs no VCS mutation or
   delegation, and runs the change's checks on its final edits. It never writes
   description text; when the revision's description no longer accounts for it,
   it returns the facts. It returns `done` with each check's command, result,
   and the commit it ran on, or `blocked` with the evidence or question. When
   the host cannot continue an agent, or this session no longer has it, such as
   after compaction, give each remaining change to a fresh implementer with the
   path of `run.md` and the change.

   Land the change when its diff does what its plan says, changes nothing else,
   and passed its checks on the tree that lands, composing any new description
   from the diff and the facts. Resolve conflicts it causes in later revisions
   as `diff-fix`'s Resolve conflicts step does. A change that does not land gets
   one more attempt from a fresh implementer briefed with the plan and the
   failure, which then carries on with the milestone; a second failure or a
   `blocked` return needs the user.

4. **Finish the milestone.** Before a later milestone starts, the milestone's
   change checks pass at the tip: the implementer reruns each one that has not
   yet passed on the tip's tree, and a failure becomes a change it plans and
   builds as step 3 does. Then record the milestone's revisions as they now
   stand and mark it `done`. When a planner or the milestone's result shows the
   pending milestones are wrong, dispatch a fresh planner to revise them, and
   record why; when it shows a `done` milestone took the wrong path, that needs
   the user.
5. Repeat from step 2 until no milestone is `pending`.

## Report

A stop before `run.md` exists only says why. Otherwise write `Outcome` to
`run.md`: `done`, `blocked`, or `stopped by user`. Lead the report with that
outcome, and list the revisions created and changed, in branch order, with
change IDs and descriptions; the bookmark; any revision left conflicted; the
planned changes and milestones that did not land; the user decisions; and the
run directory's absolute path. Unless the header names a `Then:` skill, end by
offering `diff-fix` on the run's revisions to review them.
