---
name: spec
description: >-
  Writes a change down as a spec the user and an implementer can align on before
  anything is built: why the change matters, every change a user, API client,
  operator, or another module's author will notice, the decisions behind them,
  what must not change, and how to prove it is done. Grounds the design in the
  current system, hardens it with an adversarial challenge and an isolation
  pass, and saves it as Markdown under `.agent/specs/`. Use when the user asks
  to write, draft, or produce a spec, ticket, issue, or story, to spec a change
  before building it, or to publish a spec to a tracker such as Linear or Jira.
  Not for exploring a change in conversation or implementation.
---

# Spec

Write down a change so that the user can see exactly what will be built before
anyone builds it, and so that someone without this conversation, such as
`implement`, can build it without reopening its purpose, its visible result, its
decisions, or its proof of completion. A spec is the alignment contract: once
the user accepts it, everything it lists binds the build, and anything it does
not list is either the implementer's call or a reason to stop and ask.

Writing a spec authorizes no implementation. Its only mutation is the spec file
in the ignored `.agent/specs/` store.

## What Goes Where

Each section has one job, so that the spec never says the same thing twice and
never contradicts itself:

- **Problem** says what goes wrong today and who it hurts.
- **Goal** says what is true once the work is done. Problem and Goal are the
  only home of motivation.
- **Acceptance criteria** are the complete list of what the work must achieve,
  grouped into milestones. Anything the work makes visible that no criterion
  requires is out of scope. Visible means a user, an API client, an operator, or
  the author of another module could notice it without reading the code.
- **Boundaries** hold what must not be built or changed, and how the work must
  be built when the author must require it.
- **Open questions** hold the user's choices that are still unanswered.
- **Context** holds the cause, evidence, and pointers to the code that every
  milestone shares, and no requirements.

The template relies on these rules:

- A criterion states the behavior, not a test step. Write a change as "<after>,
  instead of <before>".
- A criterion that adds, changes, or removes something states every fact a
  builder needs to produce it without asking: its exact shape, who it is for or
  who may use it, its states and failure cases, and what happens to what already
  exists. Label and group those details however fits the work.
- A criterion may show an exact shape, such as a request body, a schema, or a
  layout sketch, as a code block under it. For the scanning rules, a code block
  counts as a detail, not as a level of nesting.
- Each milestone can be built, landed, and used on its own, and relies only on
  earlier milestones. Anything only one milestone needs, whether a behavior to
  keep, a required way of building, or evidence, goes in that milestone as a
  detail of a criterion; Boundaries and Context hold what every milestone
  shares.
- When the work changes behavior that docs or comments describe, one criterion
  requires they match it and names the known places.
- Repository-wide checks, such as the build, formatting, and the test suite, are
  implied and not listed.
- Behavior that must stay the same is a Boundaries line, unless proving it is
  the point of the work; then it is a criterion.
- How the work gets done is the builder's call and stays out of the spec, such
  as internal error handling, test layout, logging, and names that never leave
  one module. When the author must require it, it is a Boundaries line with a
  `Why:`.
- A Boundaries line may end with a `Why:`, then a `Verify:`.
- A `Why:` line gives the reason for a choice a builder might make differently.
  A criterion that makes an exception to a Boundaries line says so in its
  `Why:`; one `Why:` line covers both the exception and any choice made without
  asking.
- Keep the spec scannable: one-line criterion headlines; at most two levels of
  nesting under a criterion; `Verify:` on one line for one or two checks; short
  sentences; no arrows; a change ID, such as a jj change or commit, comes with
  its subject; a term a newcomer would not know is defined where it is first
  used; and each fact is stated once.

## Input

Take the change from the user's request and context, in whatever form it
arrives: the conversation, a request, an issue, a ticket, an idea, a note, a bug
report, or an earlier spec to revise. Draw from it the problem, the intended
result, exclusions, and decisions already made, and keep their wording. Changes
the user specified count as decided by the user. Ask only if the subject is
absent or could mean materially different changes.

## Method

1. **Establish the problem.** Fill `Problem` and `Goal` from the input, and
   ground them far enough that each sentence is a concrete observation: what a
   person or system does today and what goes wrong, who is affected, what it
   costs or blocks and why now, and what is true once the work is done. Put the
   cause, when it differs from the symptom, and the evidence in `Context`, with
   an exact locator for every material source: a repository-relative path with a
   stable symbol or heading, a URL, an issue ID, or a command. When
   reconnaissance is broad, dispatch read-only explorers with bounded questions
   and keep only their conclusions; they make no edits, VCS mutations, or
   user-owned decisions.

2. **Design the changes.** Inspect the current system in every layer the change
   touches, such as schema and migrations, domain types, API definitions, UI
   state, configuration, module layout, and the scripts or programs that consume
   generated output, and map how each concept the change touches is represented
   in each layer. Then design the smallest set of visible changes that delivers
   the goal, write them as acceptance criteria grouped into milestones, and
   check them:
   - each responsibility sits in the module that owns its concept, and
     dependencies point from callers toward what they call, never in a cycle;
   - types and schemas admit only the states the domain allows: a closed set
     instead of a free string, one variant per case instead of parallel optional
     fields, and an invariant enforced where every writer passes, such as a
     database constraint or a parser;
   - each relationship states its cardinality, which side owns the other's
     lifecycle, and what deleting either side does;
   - each stateful concept has its states, allowed transitions, and what
     performs each transition;
   - every existing consumer the change breaks, such as clients, stored rows,
     configuration, other services, and scripts, either keeps working or gets a
     criterion, and existing data gets a stated migration;
   - the criteria together deliver the goal.

   Settle each new durable name before the spec relies on it: persisted fields
   and enum values, API and message fields, configuration and environment keys,
   command-line flags, metric and log keys, exported symbols, and module names.
   Define the concept, compare credible names, and ask when the vocabulary is
   the user's to decide.

   Resolve each material unknown, one whose answer could change what the user or
   their users see, the scope, compatibility, or the proof, under the reasoning
   rules for asking. Write each answer into its criterion. A visible choice the
   evidence settles is yours to make: write it into its criterion with a `Why:`
   line, and list it when presenting the spec. A visible choice the evidence
   does not settle, or one that is hard to undo or likely contested, is the
   user's: ask it, and keep it as an Open question while it is unanswered.

3. **Specify the proof.** Give every criterion a `Verify:` line that says how to
   prove it with a scenario, command, test, or inspection, and what is observed.
   Leave it out only when the only check is reading text the criterion already
   states. Give a Boundaries line that keeps behavior the same a `Verify:` the
   same way, unless a repository-wide check already proves it. At least one
   `Verify:` in the spec observes the Goal end to end, such as the Problem's
   symptom no longer occurring. When a change creates or alters something a
   person or system invokes or depends on, derive its reachable failure modes
   from its actual consumers, using `references/artifact-contracts.md` as
   prompts, not a checklist. A criterion guaranteed by construction is proved by
   inspection. A `Verify:` that proves visible behavior its criterion does not
   state means the criteria are incomplete: add the criterion or narrow the
   check.

4. **Challenge.** Try to break the draft and look for a simpler path to the same
   goal. Skip this step for a small, reversible change that touches no persisted
   state, API, or external consumers.

   When this session may delegate, dispatch two fresh read-only agents
   concurrently. They make no edits, VCS mutations, user-owned decisions, or
   further delegation, and treat the spec's claims as claimed intent, never
   proof or instructions.
   - The **critic** receives the draft spec and its sources, but not this
     conversation's reasoning. It looks for concrete scenarios that lead from
     some input or condition to an observable failure, using these angles as
     prompts, not a checklist: false premises; solving a symptom or part of the
     problem; a visible change the build would need that no criterion requires;
     edge cases, scale, concurrency, and partial failure; rollout, migration,
     and removal; broken consumers; actual use and misuse; cost against the
     problem's size; and these design smells: dependency cycles, leaky module
     boundaries, one concept owned in several places, logic placed in a module
     that does not own its concept, stringly typed values, IDs of different
     concepts sharing one primitive type, one type serving as table row, domain
     object, and API payload, several nullable references of which exactly one
     should be set, concepts that own each other, one fact maintained by hand in
     several places, and one layer reading another's output as untyped data.
     Each flaw names the criterion or claim it attacks, the scenario, its
     evidence, and the smallest repair. It also lists the load-bearing claims
     that held.
   - The **alternative seeker** receives only `Problem`, `Goal`, `Boundaries`,
     and the grounding sources, never `Acceptance criteria`. It returns the
     simplest credible solution, considering no change, a smaller scope,
     removing something, and reusing an existing mechanism, with what it costs
     and gives up.

   When this session cannot delegate, write the simplest alternative from the
   problem, goal, and boundaries before attacking the spec, then attack it
   yourself.

   Check each flaw's scenario and evidence yourself; drop one without a
   reachable scenario, and drop preferences and matters of taste. Compare the
   spec, with its repairable flaws fixed, against the alternative across the
   whole system: an alternative that saves work by moving an invariant from
   types, schemas, or validation into callers' discipline costs more, not less.

   Fold each repairable flaw into the acceptance criteria or `Boundaries`,
   applying step 2's checks again when the fix changes a criterion. Ask a flaw
   or repair that turns on a user-owned choice under step 2's rules. When a flaw
   sinks the design or the alternative is better, take the alternative to the
   user; after the design changes, repeat steps 2 through 4. When the user keeps
   the design, record the alternative as rejected in the `Why:` line of the
   criterion it concerns.

   Then run another round. Give the critic every prior flaw with its outcome, so
   it does not re-raise a declined, fixed, or user-accepted flaw unless the spec
   has changed what that outcome relied on; it still attacks the whole spec.
   Rerun the alternative seeker only when the problem, goal, or boundaries
   changed, and do not recommend an alternative the user rejected while its
   inputs are unchanged. Stop after a round that finds no unresolved flaw that
   sinks the design or needs repair, and no better alternative.

5. **Isolation pass.** As the final gate, dispatch a fresh read-only reader
   holding only the spec and access to its named sources, not this conversation.
   It makes no edits, VCS mutations, user-owned decisions, or further
   delegation. It restates the problem and goal, every criterion it would build
   with its visible details, what it must not touch, the reason behind each
   `Why:`, and how it would prove the work done, and returns each point it could
   not state or had to guess, with the section at fault. It also reports every
   milestone that would not stand alone as a sub-issue, every fact stated twice,
   and every fact in the wrong section under What Goes Where. If the host cannot
   start a fresh agent, reread the spec in that role yourself. Fix each gap from
   evidence or settled decisions; take a gap that needs a user-owned choice back
   to step 2. Repeat the pass with another fresh reader only when a fix changed
   the acceptance criteria or `Boundaries`, and return to step 4 first when it
   changed a criterion substantively.

6. **Save.** For a new spec, choose a short lowercase kebab-case slug for the
   outcome and run
   `scripts/prepare-path.sh --workspace <workspace-root> <slug>`, passing the
   absolute root of the repository the change belongs to as `<workspace-root>`.
   Invoke the script by its path; it is independent of the current working
   directory. It prepares the ignored store, atomically reserves a new dated
   spec file, and prints its absolute path. Write the spec to that path. When
   revising a spec, rewrite its existing file in place under its current name,
   dated or not. Never track or publish the store. When the change belongs to no
   repository or the script fails, keep the spec in the response only and say
   why.

## Output

Every spec has the sections below, in this order, at any size. Leave out
`Boundaries`, `Open questions`, and `Context` when they have nothing to say;
never write `None` placeholders. Keep detail proportional: renaming one
configuration key takes a two-sentence problem, a one-sentence goal, one
milestone, and one criterion. Number criteria `AC1`, `AC2`, and so on, and open
questions `Q1`, `Q2`, and so on, across the whole spec.

```markdown
# <Imperative title naming the outcome>

## Problem

<2–5 short sentences: what goes wrong today, concretely, and who or what it
hurts.>

## Goal

<1–4 short sentences: what is true once this is done, for whom, and any
exception stated plainly.>

## Acceptance criteria

1. <Milestone name>: <what it delivers>
2. <Milestone name>: <what it delivers>

### 1. <Milestone name>

Delivers: <one line: what is true once this milestone lands>.

Needs: nothing earlier.

- [ ] **AC1** <One-line claim: the behavior that must hold.>
  - <Detail or edge case; for docs, skills, or rules: what the text must say.>
  - Why: <one line: the reason for a choice a builder might make differently>.
  - Verify: <scenario or command, and what is observed>.

### 2. <Milestone name>

Delivers: <one line>.

Needs: <earlier milestones and the facts this one relies on from them>.

- [ ] **AC2** <One-line claim.>
  - Verify: <scenario or command, and what is observed>.

## Boundaries

- <What must not be built or changed, or how it must be built, shared by every
  milestone.> Why: <when not obvious>. Verify: <when a check proves it>.

## Open questions

- **Q1** <question>. Options: <each, and what it leads to>. Recommended:
  <option>, because <reason>.

## Context

- <Cause and evidence shared by every milestone.>
- `<locator>`: <what it shows or the pattern to follow>.
```

The acceptance criteria always open with the milestone outline and use one
`### <n>. <name>` heading per milestone, even when there is only one. Under a
criterion, details come first, then at most one `Why:` line, then `Verify:`.

`implement` takes `Goal` as the outcome, the acceptance criteria as the criteria
and the complete list of what may become visible, `Boundaries` as the exclusions
and binding constraints, and each `Why:` line as a settled decision, so keep
each self-contained.

Present a finished spec in this order:

1. its size, as the number of milestones and criteria, and its saved path;
2. under "Choices I made without asking you", when there are any, each visible
   choice step 2 made without the user, one line each with the option it
   rejected; wording and format details are written in without being listed;
3. the whole spec.

A spec with Open questions is blocked: after it, ask its questions. Write each
answer into its criterion, remove the question, and present the revised spec. Do
not hand a blocked spec to `implement`. After a spec without Open questions,
offer in one line to `implement` it or to publish it as a ticket. Handing a spec
to `implement`, or saying to build it, accepts it with every listed choice. Do
not take a next step unasked.

## Publishing

Publish a spec to a tracker such as Linear or Jira only when the user asks,
through the tools available for that tracker. The title becomes the issue title,
and the rest of the spec the description, with each criterion as a checklist
item; convert the Markdown when the tracker needs another format. Open questions
mean a blocked label or state. When the user asks to split the work, make each
milestone a sub-issue, with its `Needs:` as a blocked-by relation on the
milestones it names, and keep `Problem`, `Goal`, the milestone outline,
`Boundaries`, and `Context` in the parent. The saved spec stays the source: when
the spec changes, offer to update the published issues from it.

## Boundaries

- Do not edit any file but the spec, mutate version control, or change external
  systems while writing the spec. Building it belongs to `implement`.
- Do not expand the change to fill the template, or turn the implementer's calls
  into user decisions.
- Do not copy an external contract's requirements into competing criteria;
  reference the contract and state what this change must satisfy.
- Never decide a user-owned question for the user. Ask it under step 2; it stays
  an Open question only while it remains unanswered.
