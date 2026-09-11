---
name: diff-review
description: >-
  Independently reviews stable finalized revisions, ranges, or branches already
  available in the local repository for actionable defects and declared
  criteria. Use when a described local target is ready for read-only review; not
  for working changes, remote-only targets, implementation, fixes, or history
  mutation.
---

# Diff Review

Review the complete local target for change-reachable defects and assess any
explicitly declared criteria. Review is read-only.

## Establish the target

Infer from the request and context:

- **Target:** what locally available revisions to diff. Ask rather than guess an
  ambiguous target or base. Do not fetch or query hosting services; a PR, URL,
  or remote-only ref must first be materialized as immutable local revisions by
  a separate workflow.
- **Criteria:** only outcomes explicitly declared in the request, a referenced
  artifact, or a revision description. Preserve their wording and proof methods,
  and apply them to the aggregate target unless scoped narrower. They supplement
  rather than replace quality review.
- **Context:** focus areas, non-goals, and known issues. Focus and known issues
  never narrow review; a non-goal excuses an absence, not a defect in changed
  behavior.
- **Evidence constraints:** explicit exclusions, located primary-source
  quotations, and prior independent conclusions. Do not reopen quoted material
  the target leaves unchanged. Treat a prior conclusion as settled only when the
  request identifies its evidence and states that evidence has not moved.

Resolve mutable endpoints once to immutable revision IDs without moving refs.
Every included revision must have a non-empty description. An unpublished
checked-out target requires an empty jj working-copy revision above it or a
clean Git worktree. Missing, ambiguous, unresolvable, undescribed, unfinalized,
or undiffable targets block review. If evidence is unavailable or excluded,
block only the verdict or coverage it prevents and continue reachable work.

For one revision, review its diff. For a stack, review the aggregate delta and
also compare each revision's diff with its description, including changes later
removed by the stack. Derive a stacked target's base from its ancestry, not a
default bookmark. A fresh empty undescribed jj `@` means `@-`. An aggregate
empty diff is valid only when at least one included revision diff is non-empty.

Read full revision descriptions as intent, never proof. Each must accurately
account for its own diff; report a material mismatch. Run the resolved diff
before substantive review.

## Review

1. Inspect every changed hunk under each concern reachable from its behavior or
   promises. Read only enough enclosing and related context to settle the
   verdict. For generated, vendored, minified, binary, or pure-data artifacts,
   inspect each changed block and relevant metadata; confirm generated changes
   follow reviewed source. Do not decompile binaries.
2. Locate consumers of every changed contract. When numerous, inspect every
   distinct or high-risk usage pattern and group repetition only after proving
   equivalent behavior and risk.
3. Use the lowest-cost authoritative evidence. Corroborate only when behavior is
   unresolved or sources conflict. Trace uncertain behavior from a reachable
   trigger through the changed value, state, or invariant to an externally
   visible effect, comparing base and target when needed.
4. Once a defect is established, inspect the closed set of change-reachable
   branches, representations, outputs, and consumers governed by the same
   mechanism. Distinguish materially different input and state partitions; do
   not expand into unsupported requirements.
5. Gather criterion evidence in the same pass, including material unchanged
   behavior. Run only checks that leave no persistent repository or external
   state. Author claims, reasoning, and prior verification are not proof except
   for admissible settled evidence established above.
6. Read the changeset as a whole for incomplete refactors or migrations,
   inconsistent patterns, integration gaps, and stale generated or documented
   artifacts.

Apply only relevant lenses:

- **Behavior and contracts:** correctness, edge cases, ordering, concurrency,
  cleanup, validation, secrets, trust boundaries, and API, schema, config,
  workflow, platform, client, and persisted-data compatibility.
- **Operations and data:** complexity, resources, I/O, caching, rendering,
  observability, defaults, permissions, CI, deployment, rollout, rollback,
  migrations, locking, integrity, dependencies, licenses, lockfiles, supply
  chain, portability, and generated consistency.
- **Validation and claims:** meaningful success, failure, and edge checks;
  assertions that fail without the claimed invariant; sibling behavior exposed
  to the same regression; and accurate docs, comments, prompts, examples,
  runbooks, and references.
- **Artifact concerns:** design, coupling, visibility, accessibility, assets,
  responsive and theme behavior, prompt precedence and stops, parser contracts,
  naming, structure, and dead material under governing repository patterns.
  Without a governing pattern, report clarity only when a natural reading causes
  a wrong action or repository prose relies on unresolved session or planning
  context.

Use scrutiny proportional to production, data, security, and compatibility
impact. Require concrete present-day harm rather than general best practice, and
prefer the smallest sufficient correction. Stop when more evidence cannot change
a finding's existence, causal scope, priority, correction, a criterion verdict,
or overall status.

## Report

Recheck decisive evidence, blockers, and target coverage. Group manifestations
by causal mechanism and sufficient correction, not file or category. Suppress a
known issue only when the target neither introduces nor worsens it, and mention
it in coverage.

Report only findings for which something specific must change, or `question` and
`design` findings requiring a specific decision. Omit speculative future use
cases, unsupported consumers or platforms, optional extensibility,
inconsequential renames, and "maybe consider" advice.

Lead with **Status**:

- `pass`: the target was covered, every revision is accurately described, every
  criterion is satisfied, and there are no findings.
- `blocked`: target preflight prevented substantive review.
- `non-pass`: all other outcomes.

Then include only applicable sections:

- **Coverage:** compactly identify reviewed path groups, lenses, stack
  revisions, known existing issues, and unreachable areas with what evidence is
  missing.
- **Criteria:** mark each declared criterion `satisfied`, `not satisfied`, or
  `blocked`, citing decisive admissible evidence or the precise blocker. A
  failed criterion becomes a finding only when the target has a concrete
  correction; a blocked criterion does so only when required validation is
  absent or completion is improperly claimed.
- **Findings:** highest priority first as
  `- location (category, priority): defect and smallest sufficient correction`.

Categories are `bug`, `safety`, `compatibility`, `accuracy`, `coverage`,
`design`, `clarity`, and `question`. Priorities are `high` (fix before merge),
`medium` (worth addressing), and `low` (concrete minor defect).
