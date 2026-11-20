---
name: domain-model
description: >-
  Maps an existing system's type and relationship model across its typed layers,
  such as database schema, domain types, API contracts, UI state, configuration,
  and build or deployment definitions, and audits it for states the domain
  forbids and misplaced invariants. Use when the user wants to understand a
  codebase's domain or data model, or to map or audit it. Not for designing a
  change (use spec), types local to code being written (use coding-style), or
  implementation.
---

# Domain Model

Make a system's concepts, relationships, invariants, and lifecycles explicit
across every typed layer, and find where the model admits states the domain
forbids. Modeling is read-only and authorizes no implementation; to design a
change to the model, use `spec`.

## Input

Take the input from the user's request and context, in whatever form it arrives:
a system, area, concept, or the conversation. Draw from it the subject, the
layers in scope, and any decisions already made, and preserve their wording. Ask
only if the subject is absent.

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
   Spot-check the claims your findings rest on.
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
never write `None` placeholders. Keep detail proportional to the area. Include a
Mermaid `erDiagram` or `classDiagram` only where it clarifies structure the
tables do not.

```markdown
# Model: <system or area>

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
```

## Boundaries

- Do not edit files, mutate version control, or change external systems while
  modeling.
- Answer open questions beyond the model directly or leave them out of it. Route
  a change to the model to `spec` and types local to code being written to
  `coding-style`.
- Do not decide a user-owned choice the model surfaces, such as delete semantics
  or a sum type versus a table. Record it as a finding with a recommendation.
- Ground every claim in inspected evidence; mark inference as inference.
