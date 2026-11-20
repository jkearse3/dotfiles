---
name: coding-style
description: >-
  Use whenever writing, editing, generating, or refactoring source code. Makes
  code easy for search-driven agents and humans to find, understand, modify, and
  verify, applied in proportion to the change without unrelated cleanup or
  reformatting.
---

# Coding Style

Write code so a reader can reach the right implementation from task language in
a few searches, learn each symbol's contract at its definition, trust types and
durable checks to reject unsupported states, and scan its flow in coherent
paragraphs. Minimize ambiguity and navigation cost, not identifier length, file
count, or blank lines.

Scale effort to the change. Routine local edits may need only consistent
vocabulary, clear types, and coherent formatting; public interfaces,
cross-module behavior, and structural refactors warrant all of **Name and Locate
Concepts** and **Lay Out Code**. **Write Durable Checks** applies at any size,
because it depends on behavior and risk. Apply the rules in full to new files
and substantially rewritten code, and otherwise only to the code the change
introduces or materially reworks; do not move, reorder, reformat, or rework
untouched code solely to make it conform.

## Name and Locate Concepts

### Choose Names

Before naming or moving a concept, search the whole repository for its existing
terms: schema, public interfaces, code, tests, documentation, and user-facing
text. That combined usage is the repository's vocabulary; where usages conflict,
follow the durable one and report the conflict. Check candidate identifiers and
filenames for unrelated collisions. Then:

- State what the concept is in one sentence before naming it. If the sentence
  needs "and" or hedges, the concept may be two concepts or not yet understood;
  resolve that first.
- Name what a value means to its consumers, not how it is computed, where it
  came from, or which change introduced it: `expiresAt`, not `createdPlusTtl`;
  `billableSeats`, not `filteredUsers`. Check that the name reads correctly at
  call sites, queries, serialized payloads, and logs.
- Encode semantics the type does not carry: units (`timeoutMs`), time meaning
  (an instant versus a calendar date), plurality, and whether a value is derived
  or authoritative. Name booleans as predicates with an unambiguous true case
  (`isArchived`, `hasPaymentMethod`).
- Qualify generic nouns (`data`, `info`, `type`, `status`, `state`, `kind`,
  `value`, `item`, `manager`, `handler`, `util`) with the domain question they
  answer: `approvalStatus`, not `status`.
- Prefer the shortest accurate name whose search results are mostly relevant.
  Public and widely used names need more context than short-lived locals; give
  generic operations an informative object (`validateSmtpConfig`, not
  `validateConfig`); do not repeat context that is already reliably visible.
- Use one spelling per concept across its behavior, checks, and references, so
  one search finds them all. Avoid aliases and near-synonyms unless an external
  interface requires them.
- Treat filenames and directories as search terms: name concept-bearing modules
  after the behavior or domain question they answer.
- Rename an existing identifier that the change makes misleading when the
  requested scope permits the compatibility impact.

### Treat Durable Names as Decisions

Database tables, columns, and enum values; serialized, API, and message fields;
event, metric, and log keys; configuration and environment keys; command-line
flags; and exported public symbols are expensive to rename once shipped. Before
writing one:

1. Define the concept in one sentence, including what null, empty, or default
   values mean.
2. Compare at least two credible alternatives and keep the one whose natural
   reading matches the definition in every consumer: schema, code, API, and user
   interface.
3. Keep it parallel with the sibling names, states, and cardinality the behavior
   already requires.
4. Settle it in the spec the user agrees, recording the definition and the
   rejected alternatives. Ask the user when repository evidence does not decide
   the term, such as when it depends on how they or the domain's owners think
   about the concept. A durable name the agreed spec does not cover is a
   deviation to present to the user, not a choice to make alone.

Keep repository documentation that defines domain terms consistent with each
term the change introduces or changes.

### Improve Search Landings

A definition's immediate context should reveal what it does, its important
inputs and outputs, hidden constraints, and where delegated behavior lives. A
search with likely domain terms should land on the changed concept without
excessive unrelated hits.

- Split large mixed modules when distinct task-sized concepts repeatedly land
  readers in unrelated code; do not fragment cohesive code into tiny files.
- Keep orchestrators readable as a sequence of calls whose names lead to their
  implementations.

### Preserve Operational Trails

- Keep stable error codes, event names, configuration keys, and protocol values
  searchable as literals when operational lookup depends on them, without
  duplicating authoritative constants or weakening a sound data model.
- Give runtime errors and validation failures enough stable context to lead back
  to their source and concept.
- Mark retained legacy APIs as deprecated and point to the supported path.
- Document intentional non-behavior where a maintainer would reasonably search
  for an implementation that does not exist.

## Keep the Change Minimal

Before writing a helper, type, or utility, search for one that already does the
job, including code written earlier in the same change, and extend it when the
extension stays coherent. Add only the parameters, branches, indirection,
configuration, and state the requested behavior needs, with no hooks for
hypothetical callers.

## Document Symbol Contracts

Document each public or exported symbol the change introduces or materially
changes at its definition, so callers learn its contract from generated
documentation, an IDE, or an LSP without reading the implementation. Judge
internal symbols by conceptual importance rather than visibility; skip trivial
locals and obvious private helpers.

Describe purpose and caller-relevant behavior, even when the implementation
would reveal it: input and output semantics, constraints, units, ordering,
ownership, lifecycle, side effects, failure behavior, meaningful empty or
default behavior, concurrency, and security boundaries. Follow the language's
documentation conventions, describe behavior rather than implementation steps,
and do not merely restate the name or signature.

## Enforce Correctness

### Make Invalid States Unrepresentable

Prefer precise types over `any`, unstructured maps, or convention-only fields.
When code depends on an invariant (a value is present, in range, already
validated, or a workflow step has happened), enforce it with the strongest
mechanism the language and repository already provide, in this order:

1. Shape types so the invalid state cannot be constructed: tagged unions instead
   of combinations of nullable fields, required fields instead of optional ones
   that are always set, distinct ID and value types where mixing primitives is a
   realistic correctness or security risk, and exhaustive matching so a new case
   breaks the build instead of falling into a default branch.
2. Check runtime data once, where it enters, and return a type only that check
   can create, so downstream code accepts it without checking again:
   `parseEmail(raw) -> Email` replaces calls to `assertValidEmail(raw)`
   scattered across consumers.
3. Declare what remains in a layer the system already enforces, such as
   data-store constraints, configuration or interface schemas, or build-time
   checks. An invariant that spans records or concurrent writers, such as
   uniqueness or a reference to another record, belongs in the layer every
   writer passes through, even when a boundary parser also checks it.
4. Assert at runtime only when the earlier mechanisms cannot express the
   invariant or would cost more than the defect it prevents. Put the check in
   the boundary that owns the invariant, not in each consumer, and name its
   error after the violated invariant.

The urge to write an `assert`, `ensure`, or `must` helper in production code
usually means a type or declarative rule still admits a state the code does not
support; revisit steps 1 through 3 first. Test assertions are unaffected. Do not
add type-level machinery, validation libraries, or encodings whose reading cost
exceeds the risk they remove.

### Handle Failure

- Handle or propagate every error with the context **Preserve Operational
  Trails** describes; never swallow one silently. Release acquired resources on
  every path, including failure.
- Where a partial result would matter, make a mutation complete or leave state
  recoverable through atomic replace, idempotent retry, or explicit rollback.
- Escape or parameterize untrusted input before it reaches commands, queries,
  paths, or markup, and keep secrets out of logs, errors, and output.

### Write Durable Checks

Add a durable check when the change introduces or alters behavior whose failure
would matter to a caller, an external system, or persisted state, and neither
the compiler, schema, build, nor an existing check already protects it. Typical
cases are deterministic results over inputs with meaningful edge or failure
cases, including malformed or empty input; mutations of files, persistent state,
or an external system; and runtime contracts such as arguments, output streams,
exit codes, idempotence, or change detection.

Use the repository's existing check mechanism rather than a new harness. Judge
the need against repository examples of similar risk, not against whether
immediate neighbors have checks.

Confirm each new check fails when the behavior it protects breaks. Tautological
checks do not count: restating a compiler, schema, or build guarantee; asserting
a mock returns its configured value; deriving the expected value from the code
under test; or asserting on unreviewed snapshots. Mocks and fakes count when
they enforce behavior the code owns, such as request construction, call
sequencing, error handling, or suppression of a side effect, but not as evidence
of compatibility with the external system they imitate.

Run checks only against repository fixtures, temporary files, in-memory state,
explicitly provisioned disposable state, or sandboxed integrations, never
against sensitive data or protected, production, shared, or non-disposable user
state; authorized validation against such state is separate manual validation.
When representative automation is impractical, add the strongest meaningful safe
partial check, if any, and report the gap it leaves.

## Keep Cost Proportional

Where input size or I/O count is unbounded, avoid quadratic work, I/O inside
loops, and N+1 queries. Elsewhere, prefer the clearer code and optimize only on
evidence, such as a profile, benchmark, or measured regression.

## Lay Out Code

Mandatory formatters, language constraints, generated-code requirements, and
established repository conventions win where they control layout.

### Order Declarations for Progressive Disclosure

At the top level of a file, module, or namespace, after language-mandated
elements, lead each coherent region with its primary concept, public or private,
and place its supporting declarations and lower-level details beneath it; do not
group symbols merely by visibility. Keep each supporting declaration next to the
declaration that depends on it, with no unrelated helper, type, constant, or
secondary concept between them. Where the language allows references to later
declarations, order for the reader rather than by dependency.

In an existing file, place new or reworked declarations as a coherent group at
the most sensible point in the existing order rather than reordering around
them.

### Structure Code Paragraphs

Use blank lines as semantic delimiters: each paragraph performs one coherent
step. Start a new one when the code changes phase, such as preparing inputs,
consuming a validated result, moving from derivation to a side effect, changing
subject or abstraction level, or finishing setup before the main control flow.
Keep together statements whose direct relationship matters:

- an operation and its immediate error handling;
- a condition and its body;
- a declaration and the statements that directly construct its value;
- statements that jointly express one calculation or invariant;
- a comment and the code it explains.

```go
x := "thing"

y, err := do(x)
if err != nil {
	return err
}

print(y)
```

The assignment prepares the input, the call and its error check form one
operation, and the final statement consumes the successful result.

Use single blank lines, never repeated ones as stronger separators or one after
every statement; blank lines expose existing structure, not manufactured stages.
Keep compact branches and loops compact when they perform one step. When
paragraphs cannot make complex logic clear, extract, name, or comment instead.

### Format Record Construction

Write a struct, record, or object literal that initializes more than one named
field as a multiline block with one field per line, recursively for nested
record values. Empty and single-field literals may stay compact. Positional
arguments and collection elements are exempt.
