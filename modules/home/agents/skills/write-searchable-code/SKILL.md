---
name: write-searchable-code
description: >-
  Writes code that search-driven coding agents and humans can efficiently find,
  understand, and modify. Use whenever writing, editing, generating, or
  refactoring source code, including identifiers, types, modules, tests, errors,
  and comments. Apply proportionally without introducing needless verbosity,
  fragmentation, unrelated cleanup, or compatibility changes.
---

# Write Searchable Code

Write code so a reader can move from likely task language to the correct
implementation through a small number of text searches and focused reads.

Apply this skill to all source-code changes. Routine local edits may require
only consistent vocabulary and clear types. Public interfaces, cross-module
behavior, and structural refactors warrant a deliberate retrieval check.

## Inspect First

Before choosing names or moving code:

1. Search for the repository's existing terms for the concept.
2. Search candidate identifiers and filenames for unrelated collisions.
3. Inspect neighboring source, tests, public interfaces, and conventions.
4. Prefer established domain vocabulary over introducing synonyms.

Do not rename unrelated code or broaden the requested change solely to improve
discoverability.

## Make Names Searchable

- Give symbols enough domain context to distinguish them from unrelated
  concepts. Public and widely used names need more context than short-lived
  locals.
- Prefer the shortest accurate name whose search results are mostly relevant.
  Give generic operations an informative object when needed:
  `validateSmtpConfig`, not `validateConfig`.
- Use one spelling for one concept. Avoid aliases and near-synonyms unless an
  external interface requires them.
- Treat filenames and directories as search terms. Name concept-bearing modules
  after the behavior or domain question they answer.
- Respect meaningful language qualification and established framework
  conventions. Do not repeat context that is already reliably visible.
- Rename misleading identifiers when behavior changes and the requested scope
  permits the compatibility impact.

## Improve Search Landings

When a search reaches a definition, its immediate context should normally show
what it does, its important inputs and outputs, its hidden constraints, and
where delegated behavior lives.

- Add a concise definition-site comment only for information the code or type
  cannot express, such as units, ordering, ownership, security boundaries, or
  intentional missing behavior.
- Keep related behavior and tests easy to locate through the same vocabulary.
- Split large mixed modules when distinct task-sized concepts repeatedly land
  readers in unrelated code. Do not fragment cohesive code into tiny files.
- Keep orchestrators readable as a sequence of calls whose names lead to the
  implementation.

## Make Intent Checkable

- Prefer precise input and output types over `any`, unstructured maps, or
  convention-only fields.
- Use distinct ID or value types when interchangeable primitives create a
  realistic correctness or security risk.
- Represent meaningful state alternatives explicitly rather than through
  undocumented combinations of nullable fields.
- Make invalid usage fail through the compiler, schema validation, or focused
  runtime validation when practical.
- Name important types and validation errors so diagnostics lead back to the
  relevant concept.

## Preserve Operational Trails

- Keep stable error codes, event names, configuration keys, and protocol values
  searchable as literals when operational lookup depends on them.
- Give runtime errors enough stable context to locate their source.
- Mark retained legacy APIs as deprecated and point to the supported path.
- Document intentional non-behavior where a maintainer would reasonably search
  for an implementation that does not exist.

Do not duplicate authoritative constants or weaken a sound data model merely to
repeat strings. Prefer one source of truth when drift is the greater risk.

## Check Retrieval

For each materially changed concept:

1. Search using domain words a maintainer would likely use.
2. Confirm the relevant file or symbol appears without excessive unrelated hits.
3. Confirm the landing context identifies the implementation or its next
   delegation.
4. Confirm tests use discoverable, consistent vocabulary.
5. Run the project's focused type, lint, and test checks.
6. Inspect the diff for unnecessary renaming, comments, modules, or API changes.

Optimize ambiguity and navigation cost, not identifier length or file count.
