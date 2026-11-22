---
name: implement
description: >-
  Implements a requested change in a jj repository as finalized revisions: new
  ones, changes folded into existing ones, or both. Plans a roadmap of
  milestones, gives each milestone to one fresh implementer subagent that plans
  it from the code already landed and builds its changes while this session
  lands each one. Builds an agreed spec; without one, first drafts a spec and
  waits for the user to agree it. Use when the user asks to implement, build, or
  carry out a change from any input: a request, issue, plan, note, or spec. To
  implement and then review in one go, use iterate. Not for fixing review
  findings (use diff-fix), read-only investigation or review, Git-only
  checkouts, or publication.
---

# Implement

Turn a described change into finalized, independently valid revisions on the
user's current branch. This session keeps the run record, lands each change, and
asks the user; subagents plan, edit, and run checks. If the host cannot start
fresh agents, stop and report.

Agree with the user what the change makes visible first. Then plan the whole
task coarsely and only the next milestone in detail, from the code that has
landed. One implementer plans and builds each milestone, so the agent that
explored the code is the one that changes it.

## Input

Take the change from the request and context: the request itself, a file, an
issue, a note, a plan, a spec, or the conversation. Draw from it the outcome,
criteria, exclusions, settled decisions, and binding requirements such as
constraints and prescribed implementation details, keeping their wording. From a
spec in the shape `spec` defines, take `Goal` as the outcome, the acceptance
criteria as the criteria and the complete list of what may become visible,
`Boundaries` as the exclusions and binding constraints, and each `Why:` line as
a settled decision. A spec with a `Changes` section predates that shape; take it
as plain input, so step 1 redrafts it. Read a referenced artifact only as far as
needed to hand it on; do not explore the codebase here. Settled decisions count
as user decisions.

## Outcomes

Hold these throughout, choosing the jj commands; when one cannot hold, that
needs the user.

- **One branch.** The run works on the branch `@` sits on (`mutable() & ::@-`)
  plus the revisions it adds. It starts only from an empty, undescribed `@` on a
  linear branch of described revisions; otherwise stop and say why. When the
  request names a revision off that branch, ask the user to check out its
  branch.
- **Valid history.** Every revision the run creates or changes holds one
  concern, is described as `finalize-changes`'
  `references/revision-descriptions.md` requires, and is valid on its own under
  `finalize-changes`' Sequencing. A change lands in a new revision or in the
  existing revision whose concern it belongs to, and later revisions that use it
  are updated to match.
- **Nothing else moves.** No revision off the branch changes. On it, folds and
  conflict resolutions rewrite what the version-control rules allow in the
  task's stack, plus any revision the request names.
- **A bookmark marks the tip.** The task bookmark always points at the branch's
  tip.
- **A clean working copy.** Between changes and when asking the user, as at the
  end, `@` is an empty child of the tip with no unlanded attempt on the branch.
- **Resumable.** `run.md` holds enough to resume after compaction.

Before the first planner, run
`scripts/prepare-run.sh --workspace <workspace-root> <slug>` by its path, with
the workspace's absolute root and a short slug for the outcome. It prepares the
ignored `.agent/implement/` store and prints a new run directory's absolute
path. On failure, never fall back to the scratchpad or the workspace. Never
track, publish, or delete the store or a run directory. Invoking this skill
authorizes writing them and abandoning attempts that did not land.

## Run Record

`run.md` in the run directory is the source of truth. Only this session writes
it, whenever it changes; subagents read it. After compaction, or whenever memory
and the file could differ, reread it and any skill its `Then:` names; after
Report, continue with that skill's next step. It holds:

- a header: workspace path, branch base, bookmark, input source, and, when the
  invoking skill asks, `Then:` naming the skill that follows;
- `Input`: the outcome, criteria, exclusions, settled decisions, and binding
  requirements verbatim, or, for an input file in the run store's `.agent/`
  directory, its path and which sections hold each;
- `Decisions`: each user answer, dated, and each decision the skill `Then:`
  names records, prefixed with the name of the skill that took it;
- `Spec`: the path of the agreed spec with the date the user agreed it or handed
  it over; or, quoting `Input` or with the evidence, that `Input` itself
  specifies every visible change or that the change makes none;
- `Roadmap`: ordered milestones, each with its goal, the spec milestone it
  builds when the run has an agreed spec, the criteria it completes, and
  `pending` or `done` with the revisions it created or changed and their
  unsettled suspected defects;
- `Current milestone`: its changes, each `pending` or `landed` with the revision
  it created or changed, its check reports, and its unsettled suspected defects;
- `Outcome`, written at the end.

## Loop

Planners, and implementers while they plan, work read-only: no edits, VCS
mutation, scratch files in the repository, or delegation. Each gets the path of
`run.md` and `finalize-changes`' Sequencing section verbatim, and returns its
questions and the defaults it chose instead of asking. Show the defaults, ask
the questions, record the answers, and send them back to the agent that planned
when they change its plan.

When something needs the user, ask, offering decide or stop. A decision goes to
the agent whose plan it changes: the current milestone's implementer, or a fresh
planner for pending milestones or landed work, which revises them. Dropping or
changing a criterion, settled decision, binding requirement, or anything in the
agreed spec needs the user. Stop goes to Report.

1. **Spec.** When `Input` is a spec in the shape `spec` defines that the user
   agreed or handed over to build, and it has no Open questions, record it in
   `Spec` and continue. When it has Open questions, ask them before anything is
   built, and give the answers to a fresh planner that returns the spec with
   each answer written into its criterion and the question removed, as a draft.
   For any other input, a fresh planner explores as far as needed and returns,
   with the evidence, whether the change adds, changes, or removes anything
   visible as the Alignment rule defines it, and whether `Input` itself
   specifies every such change, such as a request to rename one named
   configuration key to another; a spec with a `Changes` section never counts as
   specifying it. When the change makes nothing visible, or `Input` specifies
   all of it, record that in `Spec` and continue without waiting. Otherwise the
   planner designs the change as `spec`'s step 2 does and returns a draft spec
   in the shape `spec` defines. Save a draft as `spec`'s Save step does, present
   it as `spec`'s Output says, and wait: send requested changes and answers back
   to its planner and present the revised spec until the user agrees it. Record
   its path and the date in `Spec`, and take its sections into `Input` as a
   handed-over spec would be. Every later planner and implementer builds the
   agreed spec. When the run has no spec, the visible changes `Spec` records, or
   none, stand in for the agreed spec's acceptance criteria as the complete list
   of what may become visible in every later step.
2. **Roadmap.** A fresh planner explores as far as the roadmap needs and returns
   ordered milestones that build the agreed spec, and every user-owned decision
   the input leaves open across the task. A milestone is a coherent chunk of a
   few revisions that relies only on earlier milestones. The agreed spec's
   milestones, in its order, are the roadmap's milestones, because they are what
   the user agreed and may have published as sub-issues: a planner, here or when
   step 5 revises the roadmap, may split one into several roadmap milestones but
   never merges or reorders them, and each roadmap milestone names the spec
   milestone it builds alongside the criteria it completes. When `Spec` records
   that `Input` specifies every visible change or that the change makes none,
   the planner orders milestones itself; a small task is one milestone. Show the
   roadmap and continue without waiting.
3. **Plan the milestone.** For the earliest `pending` milestone, dispatch a
   fresh implementer with the path of `run.md` and the milestone. It plans from
   the branch as it stands and returns the changes in order, each with a goal,
   targets, the checks that prove it, and where it lands: a new revision above,
   or a fold into, a named revision, possibly an earlier change of this plan.
   Each change has one concern, and the plan includes the follow-up folds that
   keep later revisions valid. It also returns evidence that a later milestone
   or the agreed spec is wrong.
4. **Build and land** each change in order. Put a fresh working copy where it
   belongs and send the change to the implementer. It follows `coding-style` and
   builds the agreed spec: a change that needs something visible no criterion
   requires, would break a `Boundaries` line, or shows a criterion cannot hold
   makes it return `blocked` with the deviation and its evidence instead of
   working around it. It edits only the working copy, performs no VCS mutation
   or delegation, and runs the change's checks on its final edits. Before
   returning, it reviews its diff for defects as the Trace section of
   `diff-review`'s `references/reviewer.md` does, judged by
   `references/findings.md`, and fixes what it finds. It writes no description
   text and instead returns facts when the revision's description no longer
   fits. It returns `done` with each check's command, result, and commit and the
   suspected defects it could not settle, or `blocked` with evidence or a
   question. When the host cannot continue an agent, or this session has lost
   it, such as after compaction, give each remaining change to a fresh
   implementer with the path of `run.md` and the change.

   Land a change when its diff does what the plan says, changes nothing else,
   makes visible nothing that no criterion requires, and passed its checks on
   the tree that lands. Compose any new description from the diff and the facts
   as `finalize-changes`' Runbook step 3 does, and pass `jj describe` or
   `jj squash --message` only the value that `commit-message format` produced
   and `commit-message validate --require-body` accepted with the options
   `references/revision-descriptions.md` sets. While
   `jj log -r 'descendants(<landed revision>) & conflicts()' --reversed` lists a
   revision, run `jj new` on the earliest and send a fresh implementer the
   change of resolving its conflict while keeping that revision's intent and the
   landed change. Land the resolution as above with
   `jj squash --from @ --into <conflicted revision>`; one that does not land
   needs the user. A change that does not land gets one more attempt from a
   fresh implementer briefed with the plan and the failure, which then carries
   on; a second failure or a `blocked` return needs the user.

5. **Finish the milestone.** The next milestone starts only once every change
   check of this one passes at the tip: the implementer reruns each one not yet
   passed on the tip's tree, and a failure becomes a change it plans and builds
   as in step 4. Then record the milestone's revisions as they now stand, with
   its changes' unsettled suspected defects, and mark it `done`. When a planner
   or the milestone's result shows pending milestones are wrong, a fresh planner
   revises them and the reason is recorded; when a `done` milestone took the
   wrong path, or evidence shows the agreed spec is wrong, that needs the user.
6. Repeat from step 3 until no milestone is `pending`.

## Report

A stop before `run.md` exists only says why. Otherwise write `Outcome`: `done`,
`blocked`, or `stopped by user`. Report it, then list the revisions created and
changed in branch order with change IDs and descriptions, the bookmark, any
revision left conflicted, planned changes and milestones that did not land, the
unsettled suspected defects from `Roadmap` and `Current milestone`, the user
decisions, the agreed spec's path when one exists, and the run directory's
absolute path. Unless `Then:` names a skill, end by offering `diff-fix` on the
run's revisions.
