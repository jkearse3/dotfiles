---
name: model
description: >-
  Builds and checks a system's type and relationship model across its typed
  layers, such as database schema, domain types, API contracts, UI state,
  configuration, and build or deployment definitions. Use when the user wants to
  map an existing system's data model, audit it for representable illegal states
  or misplaced invariants, or design the target model for a proposed change. Not
  for open questions beyond the model (use investigate), types local to code
  being written (use coding-style), a full change spec (use shape), or
  implementation.
argument-hint: "[the system or area to model, or the change to design for]"
---

# Model

Make a system's concepts, relationships, invariants, and lifecycles explicit
across every typed layer, and find where the model admits states the domain
forbids. In understand mode, map the current model and its findings. In design
mode, produce the target model for a proposed change as a delta from the current
one. Modeling is read-only and authorizes no implementation.

## Input

```text
$ARGUMENTS
```

Accept the input in whatever form it arrives: a system, area, concept, proposed
change, spec draft, or the conversation. Take from it the subject, the layers in
scope, and any decisions already made, and preserve their wording. Choose
understand mode when the request is to map or audit what exists, and design mode
when it proposes a change. Ask only if the subject is absent or the mode could
mean materially different results.

## Method

Scale effort to the area: a single concept needs a few lines per step, a
subsystem needs every step. Use the prompts in each step to find material
issues, not as a taxonomy to fill.

1. **Ground.** Identify the typed layers the subject actually has, then inspect
   each one. An application typically has schema and migrations, domain types,
   API definitions and serializers, UI state, and configuration; tooling or
   infrastructure typically has option or module types, build outputs, generated
   files, and the scripts or programs that consume them. Include the boundaries
   where one layer reads another's output without a declared type. Separate
   observation from inference, and give every material source an exact locator:
   a repository-relative path with a stable symbol, a migration ID, a URL, or a
   command. When reconnaissance is broad, dispatch read-only explorers with
   bounded questions, one per layer or subsystem, and keep only their
   conclusions; they make no edits, VCS mutations, or user-owned decisions.
   Spot-check the claims your findings rest on. In design mode, ground the
   current model before proposing the target.
2. **Concept inventory.** List each domain concept and its representation in
   every layer: table, domain type, API shape, UI state, configuration key,
   option, or output. Map each representation to the others explicitly, and note
   where a concept is missing from a layer, split across several, merged with
   another, or present only by convention, as wiring repeated across modules
   with no type or collection that declares it.
3. **State counting.** For each concept, compare the states its types can
   represent with the states the domain allows. Look for parallel optional
   fields, a status with fields valid only in some statuses, and boolean flags
   whose combinations include impossible ones. Recommend the narrowest fix that
   makes illegal states unrepresentable: a sum type, an enum or validated option
   type, a `CHECK` constraint, or a separate table per variant.
4. **Relationships.** For each relationship, state cardinality, optionality on
   each side, which side owns the other's lifecycle, and what deleting either
   side does. Check that every layer agrees.
5. **Invariant enforcement.** For each invariant, state where it is enforced:
   the type, a constructor or parser, a database constraint, a build-time or
   evaluation-time check, a runtime check, or deliberately nowhere with the
   reason. An invariant spanning records or concurrent writers belongs where
   every writer passes, such as the database or the single evaluator that builds
   every output; flag one enforced only by each writer separately, and one
   checked only at runtime when an earlier layer could reject it.
6. **Lifecycles.** Model each stateful concept as a state machine: states,
   allowed transitions, and the function or endpoint that performs each one.
   Flag transitions reachable by direct field writes and non-terminal states
   with no exit.
7. **Signatures and call paths.** For the operations that create, change, or
   read the concepts, state inputs, outputs, error types, and effects; how they
   compose along the main call paths; and which layer handles each error.
8. **Change impact.** In design mode only, list every persisted type the target
   changes, the migration each change needs including backfill and rollback, and
   each consumer the change breaks, such as other services, clients, stored
   payloads, configuration, and scripts or programs that read generated outputs.

Check every step for these smells:

- **Stringly typed values:** strings where a closed set or structured value
  belongs.
- **Interchangeable primitive IDs:** IDs of different concepts sharing one
  primitive type, so one passes where another belongs.
- **DTO, row, and domain conflation:** one type serving as table row, domain
  object, and API payload, so a change to one layer leaks into the others.
- **Overloaded nullable foreign keys:** several nullable references of which
  exactly one should be set, or one reference whose target depends on another
  field.
- **Cyclic ownership:** concepts that own each other, leaving lifecycle and
  delete behavior undefined.
- **Duplicated sources of truth:** one fact maintained by hand in several places
  or formats, so an edit to one silently diverges from the others.
- **Untyped boundaries:** one layer reading another's output as raw data, such
  as untyped JSON, environment variables, or path conventions, so a change on
  one side breaks the other only at runtime.

## Output

Return the model in chat; save it through `notes` or publish it as an artifact
only when the user asks. Omit an optional section with no material content;
never write `None` placeholders. Keep detail proportional to the area. In design
mode, present each section as a delta from the current model: mark what is
added, changed, and removed, and leave unchanged parts out unless they explain a
change. Include a Mermaid `erDiagram` or `classDiagram` only where it clarifies
structure the tables do not.

```markdown
# Model: <system or area>

Mode: Understand | Design

Workspace: <repository or system identity and absolute path, when one applies>

<Optional: one paragraph on how the layers connect, from declaration to the
outputs and consumers.>

## Concepts Across Layers

<One column per typed layer the system has, named for that system.>

| Concept | <layer> | <layer> | ... |
| ------- | ------- | ------- | --- |
| <name>  | <loc>   | <loc>   | ... |

<Optional: mismatches between layers, missing representations, merged or split
concepts.>

## Relationships

<Optional: one row per relationship.>

| From | To  | Cardinality | From optional | To optional | Owner | On delete |
| ---- | --- | ----------- | ------------- | ----------- | ----- | --------- |
| <a>  | <b> | 1:N         | no            | yes         | <a>   | cascade   |

## Invariant Enforcement

- <Optional: invariant: enforced by <type | constructor or parser | DB
  constraint | build or evaluation check | runtime check | nowhere, because ...>
  at `<exact locator>`.>

## Lifecycles

- <Optional: concept: <state> -> <state> via `<function or endpoint>`; ...>

## Key Signatures And Call Paths

- <Optional: `<signature>`: inputs, outputs, error types, effects; called from
  <path>; errors handled in <layer>.>

## Findings

- **<finding>:** <evidence at `<exact locator>`>. Consequence: <what goes
  wrong>. Fix: <recommended change, or the user-owned choice it needs and the
  recommended option>.

## Change Impact

- <Optional, design only: persisted type, migration with backfill and rollback,
  or broken consumer, with its locator.>
```

## Boundaries

- Do not edit files, mutate version control, or change external systems while
  modeling.
- Route open questions beyond the model to `investigate`, types local to code
  being written to `coding-style`, and a full change spec to `shape`.
- Do not decide a user-owned choice the model surfaces, such as delete semantics
  or a sum type versus a table. Record it as a finding with a recommendation for
  the caller or user to decide; `shape` asks the user when it invokes `model` in
  design mode.
- Ground every claim in inspected evidence; mark inference as inference.
