---
name: coding-style
description: >-
  Use whenever writing, editing, generating, or refactoring source code. Make
  changes easy for search-driven agents and humans to find, understand, modify,
  and verify: name and locate concepts with consistent domain vocabulary, reuse
  existing code and keep changes minimal, document symbol contracts, enforce
  correctness with types that make invalid states unrepresentable and risk-based
  durable checks, handle failure safely, keep cost proportional on unbounded
  paths, and lay out code with progressive declaration order, semantic code
  paragraphs, and scannable record construction. Apply proportionally without
  unrelated cleanup or reformatting.
---

# Coding Style

Write code so a reader can move from likely task language to the correct
implementation with a few searches, understand each symbol's contract at its
definition, rely on types to reject unsupported states and on durable checks to
protect the rest, and scan its flow through coherent semantic paragraphs.
Optimize ambiguity, navigation cost, and scanability, not identifier length,
file count, or the number of blank lines.

Routine local edits may need only consistent vocabulary, clear types, and
coherent formatting; public interfaces, cross-module behavior, and structural
refactors warrant the retrieval and flow checks too. Apply **Write Durable
Checks** at either depth, because it depends on behavior and risk, not change
size. Do not rework code outside the requested change solely to make it conform.

## Name and Locate Concepts

### Inspect First

Before choosing names or moving code, search the whole repository for its
existing terms for the concept: schema, public interfaces, code, tests,
documentation, and user-facing text. Treat that combined usage as the
repository's vocabulary; where usages conflict, follow the durable usage and
report the conflict. Check candidate identifiers and filenames for unrelated
collisions.

### Choose Names

A name is a reader's first model of a concept. Choose it from what the concept
means, then check that it is searchable.

- Before naming a concept-bearing symbol, state what it is in one sentence. If
  the sentence needs "and" or hedges, the concept may be two concepts or not yet
  understood; resolve that before naming.
- Name what a value means to its consumers, not how it is computed, where it
  came from, or which change introduced it: `expiresAt`, not `createdPlusTtl`;
  `billableSeats`, not `filteredUsers`.
- Read the name where it is used: call sites, queries, serialized payloads, and
  logs. A name that reads wrongly there is wrong.
- Encode semantics the type does not carry: units (`timeoutMs`), time meaning
  (an instant versus a calendar date), plurality, and whether a value is derived
  or authoritative. Name booleans as predicates (`isArchived`,
  `hasPaymentMethod`) whose true case is unambiguous.
- Qualify generic nouns such as `data`, `info`, `type`, `status`, `state`,
  `kind`, `value`, `item`, `manager`, `handler`, and `util` with the domain
  question they answer: `approvalStatus`, not `status`.
- Prefer the shortest accurate name whose search results are mostly relevant.
  Public and widely used names need more context than short-lived locals; give
  generic operations an informative object: `validateSmtpConfig`, not
  `validateConfig`. Do not repeat context that is already reliably visible.
- Use one spelling for one concept across its behavior, checks, and other
  references, so a search for that spelling finds them together. Avoid aliases
  and near-synonyms unless an external interface requires them.
- Treat filenames and directories as search terms. Name concept-bearing modules
  after the behavior or domain question they answer.
- Rename an existing identifier that the change makes misleading when the
  requested scope permits the compatibility impact.

### Treat Durable Names as Decisions

Some names are expensive to change once they ship: database tables, columns, and
enum values; serialized, API, and message fields; event, metric, and log keys;
configuration and environment keys; command-line flags; and exported public
symbols. Before writing a new durable name:

1. Define the concept in one sentence, including what null, empty, or default
   values mean.
2. Compare at least two credible alternatives and keep the one whose natural
   reading matches the definition in every consumer: schema, code, API, and user
   interface.
3. Check the name against the states, cardinality, and sibling concepts the
   requested behavior already requires, so parallel names stay parallel.
4. Ask the user when the right term depends on how they or the domain's owners
   think about the concept rather than on repository evidence.
5. Report each new durable name with its rejected alternatives in the task
   summary so it can be reviewed before publication.

When repository documentation defines domain terms, keep it consistent with each
term the change introduces or changes.

### Improve Search Landings

A definition's immediate context should reveal what it does, its important
inputs and outputs, hidden constraints, and where delegated behavior lives.
Confirm that a search with likely domain terms lands on the changed concept
without excessive unrelated hits.

- Split large mixed modules when distinct task-sized concepts repeatedly land
  readers in unrelated code. Do not fragment cohesive code into tiny files.
- Keep orchestrators readable as a sequence of calls whose names lead to their
  implementations.

### Preserve Operational Trails

- Keep stable error codes, event names, configuration keys, and protocol values
  searchable as literals when operational lookup depends on them. Do not
  duplicate authoritative constants or weaken a sound data model merely to
  repeat strings.
- Give runtime errors and validation failures enough stable context to lead back
  to their source and concept.
- Mark retained legacy APIs as deprecated and point to the supported path.
- Document intentional non-behavior where a maintainer would reasonably search
  for an implementation that does not exist.

## Keep the Change Minimal

Before writing a helper, type, or utility, search for one that already does the
job, including code written earlier in the same change, and extend it when the
extension stays coherent. Add only the parameters, branches, indirection,
configuration, and state the requested behavior needs; add no hooks for
hypothetical callers.

## Document Symbol Contracts

Give each public or exported symbol the work introduces or materially changes
concise definition-site documentation, so callers understand its contract
through generated documentation, an IDE, or an LSP without reading the
implementation. Judge internal-package or module symbols by conceptual
importance rather than visibility alone; do not comment trivial locals or
obvious private helpers.

Describe purpose and caller-relevant behavior: input and output semantics,
constraints, units, ordering, ownership, lifecycle, side effects, failure
behavior, meaningful empty or default behavior, concurrency, and security
boundaries when relevant. A concise contract summary remains valuable even when
a reader could infer it from the implementation. Follow the language's
documentation conventions, describe behavior rather than narrating
implementation steps, and do not merely restate the name or signature.

## Enforce Correctness

### Make Invalid States Unrepresentable

Prefer precise input and output types over `any`, unstructured maps, or
convention-only fields.

When code depends on an invariant (a value is present, in range, already
validated, or a workflow step has already happened), enforce it with the
strongest mechanism the language and repository already provide, in this order:

1. Shape types so the invalid state cannot be constructed. Use tagged unions
   instead of combinations of nullable fields, required fields instead of
   optional fields that are always set, distinct ID and value types instead of
   interchangeable primitives where mixing them is a realistic correctness or
   security risk, and exhaustive matching so a new case breaks the build instead
   of falling into a default branch.
2. Check runtime data once, where it enters, and return a type that records the
   result. A parser or validating constructor produces a type that only it can
   create, and downstream code accepts that type without checking again:
   `parseEmail(raw) -> Email` replaces calls to `assertValidEmail(raw)`
   scattered across consumers.
3. Move what remains into a declarative layer the system already enforces, such
   as data-store constraints, configuration or interface schemas, or build-time
   checks, so the rule is declared once where the data is defined. An invariant
   that spans records or concurrent writers, such as uniqueness or a reference
   to another record, belongs in the layer every writer passes through, such as
   a data-store constraint, even when a boundary parser also checks it.
4. Fall back to a runtime assertion only when the earlier mechanisms cannot
   express the invariant, or when encoding it would cost more than the defect it
   prevents. Put the check in the boundary that owns the invariant, not in each
   consumer, and name its error after the violated invariant.

Treat the urge to write an `assert`, `ensure`, or `must` helper in production
code as a prompt to revisit steps 1 through 3: a remaining runtime check usually
means a type or declarative rule still allows a state the code does not support.
Test assertions are unaffected. Do not introduce type-level machinery,
validation libraries, or encodings whose reading cost exceeds the risk they
remove.

### Handle Failure

- Handle or propagate every error with the context **Preserve Operational
  Trails** describes; never swallow one silently. Release acquired resources on
  every path, including failure.
- Where a partial result would matter, make a mutation complete or leave state
  recoverable through atomic replace, idempotent retry, or explicit rollback.
- Never interpolate untrusted input into commands, queries, paths, or markup
  without the language's escaping or parameterization, and keep secrets out of
  logs, errors, and output.

### Write Durable Checks

Add a durable check when all of these are true:

1. The change introduces or alters behavior whose failure would matter to a
   caller, an external system, or persisted state.
2. The compiler, schema, build, or artifact construction does not guarantee the
   behavior.
3. No existing check directly protects it.

Common cases include deterministic results over inputs with meaningful edge or
failure cases, including malformed or empty input; mutations of files,
persistent state, or an external system; and runtime contracts such as
arguments, output streams, exit codes, idempotence, or change detection.

Use the repository's existing check mechanism rather than a new harness. Missing
checks among immediate neighbors are not a reason to skip one; compare with
repository examples carrying similar risk.

Do not add tautological checks, which pass whether or not the behavior is
correct: restating a compiler, schema, or build guarantee; asserting a mock
returns its configured value; deriving the expected value from the code under
test; or asserting on unreviewed snapshots. Confirm each new check fails when
the behavior it protects is broken.

Mocks and fakes count when they enforce behavior the artifact owns, such as
request construction, call sequencing, error handling, or suppression of a side
effect. They do not establish external compatibility when they merely restate
assumptions about the external system.

Durable checks use repository fixtures, temporary files, in-memory state,
explicitly provisioned disposable state, or sandboxed integrations. They never
read sensitive data or touch protected, production, shared, or non-disposable
user state; treat explicitly authorized validation against such state as
separate manual validation. If representative automation is impractical, add the
strongest meaningful safe partial check and report the remaining validation gap,
or the whole gap when no partial check is meaningful.

## Keep Cost Proportional

Where input size or I/O count is unbounded, avoid quadratic work, I/O inside
loops, and N+1 queries. Elsewhere, prefer the clearer code and optimize only on
evidence, such as a profile, benchmark, or measured regression.

## Lay Out Code

Apply these rules fully to new files and new or substantially rewritten code,
and otherwise only to the code the change introduces or materially reworks. Do
not move, reorder, or reformat untouched code, and avoid whitespace-only changes
outside it. Mandatory formatters win where they control layout.

### Order Top-Level Declarations for Progressive Disclosure

At the top level of a file, module, namespace, or equivalent scope, organize
each coherent region for progressive top-down reading. After language-mandated
elements, lead with the region's primary concept, whether public or private,
then place its supporting declarations and lower-level details beneath it.
Repeat this for each primary concept; do not group symbols merely by visibility.

Keep direct support relationships contiguous: place a supporting declaration
next to the declaration whose contract, shape, or implementation depends on it,
and do not let an unrelated helper, factory, type, constant, or secondary
concept split them. Where the language permits references to later declarations,
use that freedom for reader clarity rather than dependency-first ordering.
Language constraints, generated-code requirements, mandatory tooling, and
established repository conventions take precedence.

In an existing file, keep the declarations the change introduces or materially
reworks in a coherent local group at the most sensible point in the existing
order. When ideal placement would require broader reordering, preserve the
existing structure.

### Structure Code Paragraphs

Use blank lines as semantic delimiters: each paragraph performs one coherent
step, and a blank line signals a distinct purpose in the function's flow. Start
a new paragraph when the code changes phase, such as preparing inputs, consuming
a validated result, moving from derivation to a side effect, changing the
subject or abstraction level, or completing setup before the main control flow.

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
operation, and the final statement consumes the successful result.

Use one blank line between paragraphs, never repeated blank lines as stronger
separators or a blank line after every statement; blank lines expose existing
structure, not manufactured stages. Keep compact branches and loops compact when
they perform one step. If paragraph boundaries cannot make complex logic clear,
use extraction, naming, or comments instead.

### Format Record Construction

When a struct, record, or object literal initializes more than one named field,
write it as a multiline block with one named field or property per line, and
apply the rule recursively to nested record values. Keep empty and single-field
literals compact when clearer. Positional arguments and collection elements are
exempt.
