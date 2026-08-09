---
name: coding-style
description: >-
  Writes source code that search-driven agents and humans can efficiently find,
  understand, modify, and scan. Use whenever writing, editing, generating, or
  refactoring source code. Apply searchable naming, precise types, semantic code
  paragraphs, and durable checks for unguaranteed behavioral contracts,
  proportionally and without unrelated cleanup or reformatting.
---

# Coding Style

Write code so a reader can move from likely task language to the correct
implementation through a small number of searches and can scan each function's
control and data flow through coherent semantic paragraphs.

Apply this skill to all source-code changes. Routine local edits may require
only consistent vocabulary, clear types, and locally coherent formatting. Public
interfaces, cross-module behavior, and structural refactors warrant a deliberate
retrieval and flow check. Apply durable-check guidance at either depth; it keys
on artifact behavior and risk rather than change size.

## Write Searchable Code

### Inspect First

Before choosing names or moving code:

1. Search for the repository's existing terms for the concept.
2. Search candidate identifiers and filenames for unrelated collisions.
3. Inspect neighboring source, tests, public interfaces, and conventions.
4. Prefer established domain vocabulary over introducing synonyms.

Do not rename unrelated code or broaden the requested change solely to improve
discoverability.

### Make Names Searchable

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

### Improve Search Landings

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

### Make Intent Checkable

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

### Preserve Operational Trails

- Keep stable error codes, event names, configuration keys, and protocol values
  searchable as literals when operational lookup depends on them.
- Give runtime errors enough stable context to locate their source.
- Mark retained legacy APIs as deprecated and point to the supported path.
- Document intentional non-behavior where a maintainer would reasonably search
  for an implementation that does not exist.

Do not duplicate authoritative constants or weaken a sound data model merely to
repeat strings. Prefer one source of truth when drift is the greater risk.

## Structure Code Paragraphs

Use blank lines as semantic delimiters. Each paragraph should perform one
coherent step, and a blank line should signal that the next step has a distinct
purpose in the flow of the function.

Apply this guidance fully to new or substantially rewritten code, but do not
reformat untouched code merely to make an existing file conform.

### Form Paragraphs

Group statements that must be understood together. Start a new paragraph when
the code changes phase, such as:

- preparing inputs before performing an operation;
- moving from an operation and its validation to consuming its result;
- finishing state derivation before producing a side effect;
- changing the subject, abstraction level, or data-flow stage;
- completing setup before entering the main control flow.

Keep short, indivisible work in one paragraph. Blank lines should expose the
structure already present in the logic, not manufacture extra stages.

### Keep Atomic Groups Together

Do not insert blank lines where separation would obscure a direct relationship.
In particular, keep together:

- an operation and its immediate error handling;
- a condition and its body;
- a value declaration and the statements that directly construct it;
- adjacent statements that jointly express one calculation or invariant;
- a comment and the code it explains.

For example:

```go
x := "thing"

y, err := do(x)
if err != nil {
	return err
}

print(y)
```

The assignment establishes the input, the call and error check form one atomic
operation, and the final statement consumes the successful result.

Avoid flattening those phases together:

```go
x := "thing"
y, err := do(x)
if err != nil {
	return err
}
print(y)
```

Also avoid fragmenting the atomic operation:

```go
y, err := do(x)

if err != nil {
	return err
}
```

### Preserve Local Clarity

- Prefer one blank line between paragraphs. Do not use repeated blank lines as
  stronger separators inside a function.
- Do not add a blank line after every statement. A paragraph may contain several
  tightly related statements.
- Keep compact branches and loops compact when their internal steps are one
  coherent unit.
- Use extraction, naming, or comments rather than whitespace when the logic is
  too complex for paragraph boundaries to explain.
- Follow mandatory language formatters and established syntax conventions when
  they control or reject blank-line placement.
- Avoid whitespace-only changes outside code already touched by the requested
  work.

## Format Record Construction

When a struct, record, or object literal initializes more than one named field,
write it as a multiline block with one named field or property entry per line.
Apply the same rule recursively to nested record values so their shape remains
directly scannable.

Keep empty and single-field literals compact when that is clearer. This rule
does not require one-per-line formatting for positional arguments or collection
elements. Follow a mandatory formatter when the language controls the layout.

## Write Durable Checks

Write a durable check when work introduces or changes behavior whose failure
would matter to a caller or persisted state, the artifact's construction does
not guarantee it, and no existing check directly protects it. Common cases
include artifacts that:

- Produces deterministic behavior over an input domain with meaningful edge or
  failure cases, including malformed and empty inputs a caller can supply.
- Mutates files, persistent state, or an external system.
- Is invoked by or depended on under a runtime contract by a person or another
  system, such as arguments, output streams, exit codes, idempotence, or
  change-detection behavior.

A compiler, schema, or build guarantee can satisfy the construction clause; do
not add a check that merely restates it.

Use the mechanism the build already offers rather than introducing a harness.
Missing checks in immediate neighbors are not a reason to skip one; compare the
artifact with repository behavior carrying comparable risk.

Durable checks must use repository fixtures, temporary files, in-memory state,
explicitly provisioned disposable state, or sandboxed integrations. They must
not read sensitive data or access or mutate protected, production, shared, or
non-disposable user state. Treat explicitly authorized validation against such
state as separate manual validation.

Mocks and fakes count when they enforce behavior the artifact owns, such as
request construction, call sequencing, error handling, or suppression of a side
effect. They do not establish external compatibility when they merely restate
assumptions about the external system.

If representative automation is not practical, add the strongest meaningful safe
partial check and report the remaining validation gap. If no meaningful partial
check exists, report the whole gap. Do not touch sensitive state or add a
disproportionate harness solely to satisfy this section.

## Check The Result

For each materially changed concept:

1. Search using domain words a maintainer would likely use.
2. Confirm the relevant file or symbol appears without excessive unrelated hits.
3. Confirm the landing context identifies the implementation or its next
   delegation.
4. Confirm tests use discoverable, consistent vocabulary.
5. Scan each changed function and confirm each paragraph has one semantic
   purpose, each blank line marks a real transition, and directly related
   statements remain together.
6. Confirm multi-field record construction has one named field or property entry
   per line, including in nested record values.
7. Confirm the paragraph sequence communicates the function's control and data
   flow without requiring line-by-line parsing.
8. Confirm every artifact covered by **Write Durable Checks** has the strongest
   practical safe coverage and explicitly reports any remaining validation gap.
9. Run the project's formatter and focused type, lint, and test checks.
10. Inspect the diff for unnecessary renaming, comments, modules, API changes,
    or whitespace-only changes.

Optimize ambiguity, navigation cost, and semantic scanability, not identifier
length, file count, or the number of blank lines.
