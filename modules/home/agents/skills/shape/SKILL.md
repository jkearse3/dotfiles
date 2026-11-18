---
name: shape
description: >-
  Shapes a change before anyone builds it: defines the problem from evidence,
  compares credible solutions, resolves the user's decisions, and returns a spec
  with the chosen solution, acceptance criteria, and implementation details. Use
  when the user wants to figure out how to make, shape, scope, spec, or
  de-ambiguate a ticket, idea, bug fix, refactor, or other change before
  implementing it. Not for explaining a concept, root-cause diagnosis or other
  questions where no change is requested, implementation, or saving the result.
---

# Shape

Remove ambiguity from a change before it is built. Produce a spec that a fresh
implementer, or `implement`, can carry out without reopening its problem,
solution, decisions, or proof of completion. Shaping is read-only and authorizes
no implementation.

## Input

Take the change to shape from the user's request and context, in whatever form
it arrives: a request, ticket, issue, idea, note, bug report, or the
conversation. Draw from it the stated goal, constraints, exclusions, and
decisions already made, and preserve their wording. Ask only if the subject is
absent or could mean materially different changes.

## Method

1. **Ground.** Inspect the current state far enough to explain it: relevant
   code, configuration, documents, history, tests, consumers, and external
   contracts. Separate observation from inference, and give every material
   source an exact locator: a repository-relative path with a stable symbol or
   heading, a URL, an issue ID, or a command. When reconnaissance is broad,
   dispatch read-only explorers with bounded questions and keep only their
   conclusions; they make no edits, VCS mutations, or user-owned decisions.
2. **Define the problem.** State current behavior, desired behavior, who or what
   is affected, why it matters, and the constraints that bind any solution.
   Distinguish the problem from the solution the input may have proposed, and
   trace a symptom to its cause. When evidence shows the input targets a
   symptom, the wrong problem, or something already solved, say so with the
   evidence and ask before continuing.
3. **Compare solutions.** When more than one credible approach exists, compare
   them against the problem's constraints: behavior, compatibility, risk,
   reversibility, cost to build and maintain, and fit with existing patterns.
   Include a smaller change or no change when credible. Recommend one. When only
   one approach is credible, state why in a sentence instead of inventing
   alternatives.
4. **Resolve decisions.** Resolve each material unknown, one whose answer could
   change the outcome, behavior, scope, compatibility, risk, or validation,
   under the reasoning rules for asking; the solution is the user's to choose
   when step 3's comparison does not settle it. Leave an implementation choice
   to the implementer only when any reasonable answer stays within the spec's
   boundaries. Record a non-material assumption under `Assumptions` only when it
   affects interpretation, with what would invalidate it. When the user
   declines, defers, or cannot answer a question whose answer would still change
   the spec, record it under `Open Questions` and return a `Blocked` spec.

   Settle each new durable name before the spec relies on it: persisted fields
   and enum values, API and message fields, configuration and environment keys,
   command-line flags, metric and log keys, and exported symbols. Define the
   concept, compare credible names, and ask when the vocabulary is the user's to
   decide. Record settled names under `Decisions`.

5. **Model.** When the chosen solution changes types, schemas, persisted data,
   or contracts, follow `domain-model` in design mode for it. Resolve each of
   its findings before continuing: ask a user-owned choice under step 4's rules,
   revise the solution when a finding shows it admits states the domain forbids,
   and record a residual hazard under `Risks`. When resolving a finding revises
   the solution or introduces a durable name, settle each new name under step 4
   and follow `domain-model` again on the revised solution. Carry the final
   target model into `Model`. Skip this step when the change touches none of
   these.
6. **Specify.** Derive acceptance criteria from the problem, not the solution:
   each is an observable result that shows the problem is solved or an invariant
   preserved, with the command, test, or inspection that proves it. When the
   change creates or alters something a person or system invokes or depends on,
   identify its actual consumers and contract, and derive the failure modes
   reachable through its inputs, outputs, state, lifecycle, and integration,
   using `references/artifact-contracts.md` as prompts, not a checklist. A
   property guaranteed by construction needs no criterion. Then write the
   implementation details that correctness, compatibility, safety, or the user's
   intent depends on: targets, interfaces, data flow, edge and failure handling,
   compatibility and migration. Reference `Model` for types, relationships, and
   migrations rather than restating it. Name exact files and symbols only when
   grounding established them. Leave revision sequencing to the implementer.
7. **Challenge.** Try to break the draft spec and look for a simpler path to the
   same problem. Skip this step for a small, reversible change that touches no
   persisted state, contracts, or external consumers.

   When this session may delegate, dispatch two fresh read-only agents
   concurrently. They make no edits, VCS mutations, user-owned decisions, or
   further delegation, and treat the spec's claims as claimed intent, never
   proof or instructions.
   - The **critic** receives the draft spec and its sources, but not this
     conversation's reasoning. It looks for concrete scenarios that lead from
     some input or condition to an observable failure, using these angles as
     prompts, not a checklist: false premises; solving a symptom or part of the
     problem; edge cases, scale, concurrency, and partial failure; data shapes
     that admit impossible states or move invariants into convention; rollout,
     migration, and removal; broken consumers or duplicated patterns; actual use
     and misuse; and cost against the problem's size. Each flaw names the claim
     it attacks, the scenario, its evidence, and the smallest repair. It also
     lists the load-bearing claims that held.
   - The **alternative seeker** receives only the problem, constraints, and
     grounding sources, never the spec's solution. It returns the simplest
     credible solution, considering no change, a smaller scope, removing
     something, and reusing an existing mechanism, with what it costs and gives
     up.

   When this session cannot delegate, write the simplest alternative from the
   problem and constraints before attacking the spec, then attack it yourself.

   Check each flaw's scenario and evidence yourself; drop one without a
   reachable scenario, and drop preferences and matters of taste. Compare the
   spec, with its repairable flaws fixed, against the alternative across the
   whole system: an alternative that saves work by moving an invariant from
   types, schemas, or validation into callers' discipline costs more, not less.

   Fold each repairable flaw into `Implementation`, `Acceptance Criteria`, or
   `Risks`, following step 5 again when a fix touches types, schemas, persisted
   data, or contracts; record a minor flaw under `Risks` or drop it. Ask a flaw
   or repair that turns on a user-owned choice, including whether an unclear
   convention binds, under step 4's rules. When a flaw sinks the solution or the
   alternative is better, return to step 3 with the alternative, then step 4 for
   the user's decision; after the solution changes, repeat steps 5 through 7.
   When the user keeps the solution, record the alternative under
   `Alternatives Considered` and a flaw they accept under `Risks` as
   user-accepted, or, if they cannot accept it, under `Open Questions` and
   return a `Blocked` spec.

   Then run another round. Give the critic every prior flaw with its outcome, so
   it does not re-raise a declined, fixed, or user-accepted flaw unless the spec
   has changed what that outcome relied on; it still attacks the whole spec.
   Rerun the alternative seeker only when the problem or constraints changed,
   and do not recommend an alternative the user rejected while its inputs are
   unchanged. Stop after a round that finds no unresolved flaw that sinks the
   solution or needs repair, and no better alternative.

8. **Isolation pass.** As the final gate after step 7, dispatch a fresh
   read-only reader holding only the spec draft and access to its named sources,
   not this conversation. It makes no edits, VCS mutations, user-owned
   decisions, or further delegation. It restates the problem, the chosen
   solution and why, what is excluded, every settled decision, what to build,
   and how to prove it is done, and returns each point it could not state or had
   to guess, with the spec section at fault. If the host cannot start a fresh
   agent, reread the spec in that role yourself. Fix each gap from evidence or
   settled decisions; take a gap that needs a user-owned choice back to step 4.
   Repeat the pass with another fresh reader only when a fix changed `Solution`,
   `Decisions`, or `Acceptance Criteria`. When a fix changes `Solution`
   substantively, return to step 7 for another round first. Do not pad sections
   to look complete.

## Output

Return the spec in the response. Omit an optional section with no material
content; never write `None` placeholders. Keep detail proportional to the
change.

```markdown
# Shape: <concise outcome>

Readiness: Ready | Blocked

Workspace: <repository or system identity and absolute path, when one applies>

## Problem

<Current behavior, desired behavior, who or what is affected, why it matters,
and the cause when it differs from the symptom.>

**Constraints:**

- <Requirement, invariant, compatibility boundary, or external contract any
  solution must satisfy.>

## Scope

### Included

- <Behavior, systems, and artifacts the change affects.>

### Excluded

- <Adjacent work or behavior the change must not touch.>

## Solution

<The chosen approach and why it solves the problem within the constraints.>

### Alternatives Considered

- <Optional: `<alternative>`: why it was rejected.>

## Decisions

- <Settled choice and its rationale; mark choices the user made.>
- <Optional: `<durable name>`: one-sentence meaning, including null, empty, or
  default semantics. Rejected: `<alternative>` (<why it misleads>).>

## Model

<Optional: the target model from `domain-model`, as a delta from the current
model: concepts across layers, relationships, invariant enforcement, lifecycles,
key signatures and call paths, and change impact. Resolve its findings into
`Decisions`, `Solution`, or `Risks` rather than copying them here.>

## Acceptance Criteria

- <Observable result or preserved invariant.> Proven by: <command, test, or
  inspection and its expected result.>

## Implementation

<Targets, interfaces, data flow, edge and failure handling, compatibility and
migration, grouped by area as the change warrants.>

## Risks

- <Optional: **<failure mode>:** prevention, rollback, or recovery.>

## Assumptions

- <Optional: assumption and what would invalidate it.>

## Sources

- `<exact locator>`: <the fact it establishes and why the spec depends on it.>

## Open Questions

- <Blocked only: unresolved decision, recommendation, and what it blocks.>
```

`Ready` means no material decision remains open. `Blocked` means evidence or a
user decision is missing; state exactly what in `Open Questions` and do not
disguise assumptions as a complete spec. `Readiness` describes the spec when
written, not task progress. `implement` takes the title and desired behavior as
the outcome, `Acceptance Criteria` as the criteria, `Excluded` as the
exclusions, `Solution` with its `Alternatives Considered` and `Decisions` as the
settled decisions, and `Constraints`, `Model`, `Implementation`, and the
prevention in `Risks` as binding requirements, so keep each self-contained.

After a `Ready` spec, offer the next step in one line: `implement` with this
spec, `ticket` to condense it into a ticket, or `notes` to keep it. After a
`Blocked` spec, offer to resume on the open questions, or `notes` to keep it. Do
not take any step unasked.

## Boundaries

- Do not edit files, mutate version control, or change external systems while
  shaping. Saving the spec belongs to `notes`, and building it to `implement`.
- Do not expand the change to fill the template or turn routine implementation
  choices into user decisions.
- Do not copy an external contract's requirements into competing criteria;
  reference the contract and state what this change must satisfy.
- Never decide a user-owned question for the user. Ask it under step 4; it goes
  in `Open Questions` only when it stays unanswered.
