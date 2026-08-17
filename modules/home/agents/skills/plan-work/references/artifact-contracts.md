# Artifact Contract Prompts

Use these prompts after identifying the artifact's actual consumers and
contracts. Derive only concerns reachable through those interfaces and carrying
risk material to the planned work.

These are prompts, not mandatory requirements or artifact classes. Do not copy
them into a plan or explain why irrelevant prompts were omitted. A property
guaranteed by construction is not a completion condition. Material behavior that
is not guaranteed needs a durable check where practical and otherwise a proof
method a reviewer can rerun.

Place each result once where it belongs:

- `Acceptance Criteria`: externally observable behavior and preserved
  invariants.
- `Context`: relevant evidence and settled decisions.
- `Requirements` or optional `Design`: cross-cutting constraints, choices, and
  tradeoffs.
- `Work`: concern-local implementation and failure handling.
- Work-level `Validate`: proof required before dependent work proceeds.
- `Final Validation`: end-to-end checks, inspections, and rerunnable proof not
  already established by a work-level check.
- `Risks And Recovery`: residual exposure, rollback, and recovery.

## Inputs And Outputs

- Which valid, boundary, malformed, empty, truncated, deeply nested, or unknown
  inputs can actual callers provide?
- Do malformed or unsupported inputs fail explicitly rather than crash, silently
  default, or produce output the consumer cannot use?
- Where promised, does conversion or round-tripping preserve meaning or value?
- Which encoding, escaping, delimiter, ordering, or normalization cases occur in
  real inputs?
- Do defaults, precedence, and merge behavior match the consumer contract?
- Are unknown or extra fields rejected or preserved deliberately and
  consistently across every path?
- Are results and diagnostics delivered through the channels and formats callers
  interpret?
- Do failures identify an actionable field, position, argument, or condition?

## State And Mutation

- Is repeated invocation safe, and is idempotence required?
- Does already-correct input remain observably unchanged when callers depend on
  content, metadata, or change detection?
- What can interruption or concurrent access expose?
- Must replacement be atomic, or must permissions, symlinks, or inode identity
  be preserved? Decide from caller requirements rather than assuming both.
- Can partially completed work be resumed, retried, reversed, or recovered?
- What approval or preview is required before a hard-to-reverse effect?

## Invocation And Lifecycle

- What arguments, environment, working directory, input streams, and discovery
  mechanism does the host actually supply?
- How does behavior change without a TTY or with input from a pipe or file?
- Which exit statuses, output streams, responses, or signals does the host
  interpret?
- What happens on timeout, cancellation, repeated invocation, or host shutdown?
- Does a fault fail cleanly rather than wedging its host or leaving partial
  state?
- Is the artifact discoverable from a clean checkout without an undocumented
  manual step?

## Compatibility And Persistence

- Which existing consumers, stored data, or generated artifacts can the change
  affect?
- What compatibility direction and deployment order are required?
- Must old and new readers coexist during rollout?
- Is a migration reversible or deliberately one-way, and can it resume after
  interruption?
- Can migration complete within the operator's window at real data volume?
- Does generated output validate against its consumer and remain deterministic?
- Can committed generated output drift from its source, and how is drift
  detected?
- Are deprecation, ownership, and removal decisions explicit when compatibility
  is temporary?

## Agent Instructions

- Do higher-priority or sibling instructions conflict with the new behavior?
- Does routing reach every intended situation without claiming unrelated work?
- For each gate or category list, do cases derived from the final text land on
  the intended side?
- Are permission boundaries and stop conditions stated where the agent decides?
- Does a fresh agent reading only the final text take the intended action on
  cases it derives itself?
- Does retained evidence identify the cases, result, and method well enough for
  a reviewer to rerun the interpretation check?
- Are result blocks, exact strings, and other parser-facing contracts preserved?
