---
name: coding-style
description: >-
  Use whenever writing, editing, generating, or refactoring source code. Make
  changes easy for search-driven agents and humans to find, understand, modify,
  and verify through consistent domain vocabulary, precise types, semantic code
  paragraphs, scannable record construction, and risk-based durable checks.
  Apply proportionally without unrelated cleanup or reformatting.
---

# Coding Style

Write code so a reader can move from likely task language to the correct
implementation with a few searches, then scan its control and data flow through
coherent semantic paragraphs.

Apply this skill to every source-code change. Routine local edits may need only
consistent vocabulary, clear types, and coherent formatting. Public interfaces,
cross-module behavior, and structural refactors warrant deliberate retrieval and
flow checks. Apply durable-check guidance at either depth because it depends on
behavior and risk, not change size.

## Write Searchable Code

### Inspect First

Before choosing names or moving code:

1. Search for the repository's existing terms for the concept.
2. Check candidate identifiers and filenames for unrelated collisions.
3. Inspect neighboring source, tests, public interfaces, and conventions.
4. Prefer established domain vocabulary over new synonyms.

Do not rename unrelated code or broaden the requested change solely to improve
discoverability.

### Choose Searchable Names

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

A definition's immediate context should normally reveal what it does, its
important inputs and outputs, hidden constraints, and where delegated behavior
lives.

- Keep related behavior and checks easy to locate through the same vocabulary.
- Split large mixed modules when distinct task-sized concepts repeatedly land
  readers in unrelated code. Do not fragment cohesive code into tiny files.
- Keep orchestrators readable as a sequence of calls whose names lead to their
  implementations.

### Document Symbol Contracts

Give each public or exported API symbol introduced or materially changed by the
work—such as a function, type, field, or constant—concise definition-site
documentation so callers can understand its contract through generated
documentation, an IDE, or an LSP without reading the implementation. Treat
visibility limited to an internal package, crate, or module according to the
symbol's conceptual importance rather than visibility alone. Do not comment
trivial locals or obvious private helpers mechanically, or expand the requested
scope to remediate unrelated documentation gaps.

Describe the symbol's purpose and caller-relevant behavior. Include important
input and output semantics, constraints, units, ordering, ownership, lifecycle,
side effects, failure behavior such as returned errors, exceptions, or panics,
meaningful empty or default behavior, concurrency, and security boundaries when
relevant. A concise contract summary remains valuable even when a reader could
infer it from the implementation.

Follow the language's documentation conventions so tools associate the text with
the symbol. Describe behavior rather than narrating implementation steps, avoid
merely restating the name or signature, and update the documentation when the
contract changes.

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

### Keep Repository Text Self-Contained

Comments, docstrings, documents, and fixtures must be understandable from the
repository alone or from a cited, resolvable external artifact. Never rely on
the plan, ticket prose, session, or agent workflow that produced the change.
References to internal planning structure—plan or phase names, stage or step
numbers, task or milestone labels, or the producing agent's workflow state—carry
no durable meaning and must not appear.

Describe what the code does and why in durable terms. Cite an issue ID or stable
design document only when that reference adds information a later reader can
resolve.

## Structure Code Paragraphs

Use blank lines as semantic delimiters. Each paragraph should perform one
coherent step; a blank line should signal a distinct purpose in the function's
flow.

Apply this fully to new or substantially rewritten code. Do not reformat
untouched code merely to make an existing file conform.

Start a new paragraph when the code changes phase, such as preparing inputs,
consuming a validated result, moving from derivation to a side effect, changing
the subject or abstraction level, or completing setup before the main control
flow. Keep short, indivisible work in one paragraph.

Do not separate statements whose direct relationship matters. Keep together:

- an operation and its immediate error handling;
- a condition and its body;
- a declaration and the statements that directly construct its value;
- statements that jointly express one calculation or invariant;
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

The assignment prepares the input, the call and error check form one atomic
operation, and the final statement consumes the successful result. Do not
flatten these phases or put a blank line between an operation and its error
check.

Prefer one blank line between paragraphs. Do not use repeated blank lines as
stronger separators or put a blank line after every statement; blank lines
should expose existing structure, not manufacture stages. Keep compact branches
and loops compact when they perform one coherent step. If paragraph boundaries
cannot make complex logic clear, use extraction, naming, or comments instead.
Follow mandatory formatters and syntax conventions, and avoid whitespace-only
changes outside code touched by the requested work.

## Format Record Construction

When a struct, record, or object literal initializes more than one named field,
write it as a multiline block with one named field or property per line. Apply
the rule recursively to nested record values so their shape remains scannable.

Keep empty and single-field literals compact when clearer. This rule does not
require one-per-line formatting for positional arguments or collection elements.
Follow a mandatory formatter when the language controls layout.

## Write Durable Checks

Add a durable check when all of these are true:

1. The change introduces or alters behavior whose failure would matter to a
   caller, an external system, or persisted state.
2. The compiler, schema, build, or artifact construction does not guarantee the
   behavior.
3. No existing check directly protects it.

Common cases include behavior that:

- computes deterministic results over inputs with meaningful edge or failure
  cases, including caller-supplied malformed or empty input;
- mutates files, persistent state, or an external system; or
- exposes a runtime contract such as arguments, output streams, exit codes,
  idempotence, or change detection.

Use the repository's existing check mechanism rather than introducing a new
harness. Missing checks among immediate neighbors are not a reason to skip one;
compare behavior with repository examples carrying similar risk. Do not add a
check that merely restates a compiler, schema, or build guarantee.

Durable checks must use repository fixtures, temporary files, in-memory state,
explicitly provisioned disposable state, or sandboxed integrations. They must
not read sensitive data or access or mutate protected, production, shared, or
non-disposable user state. Treat explicitly authorized validation against such
state as separate manual validation.

Mocks and fakes count when they enforce behavior the artifact owns, such as
request construction, call sequencing, error handling, or suppression of a side
effect. They do not establish external compatibility when they merely restate
assumptions about the external system.

If representative automation is impractical, add the strongest meaningful safe
partial check and report the remaining validation gap. If no meaningful partial
check exists, report the whole gap. Do not touch sensitive state or add a
disproportionate harness solely to satisfy this section.

## Check the Result

For each materially changed concept:

1. Search with likely domain terms. Confirm the relevant file or symbol appears
   without excessive unrelated hits and its landing context identifies the
   implementation or next delegation.
2. Confirm symbols covered by **Document Symbol Contracts** have concise,
   conventionally formatted documentation of their contracts.
3. Confirm related behavior and checks use consistent, discoverable vocabulary.
4. Scan changed functions for coherent semantic paragraphs and atomic groups.
5. Confirm multi-field record construction uses one named field or property per
   line, including nested records.
6. Confirm behavior covered by **Write Durable Checks** has the strongest
   practical safe coverage, and report any remaining validation gap.
7. Run the project's formatter and focused type, lint, and test checks.
8. Inspect the diff for unnecessary renaming, comments, modules, API changes,
   whitespace-only changes, and repository text that depends on internal
   planning or workflow context.

Optimize ambiguity, navigation cost, and semantic scanability—not identifier
length, file count, or the number of blank lines.
