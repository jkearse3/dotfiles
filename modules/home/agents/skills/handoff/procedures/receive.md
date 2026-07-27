# Receive

Use this procedure for discovery, display, readiness reconciliation, and
explicit execution. These operations never add lifecycle state to a handoff.

## Resolve

Resolve an explicit path first, then an exact filename, then a unique slug
fragment or clear natural-language match. For discovery, run
`lib/resolve-store.sh` relative to the skill directory and search recursively
below `<canonical-root>/.agent/handoffs/`. Ask the user to choose when multiple
artifacts match. If none match, say so and report recent candidates when readily
available.

## Find, Show, Or Summarize

For a listing, report matching paths and purposes when readily available. When
showing, print the complete prompt in a fenced Markdown block unless a summary
was requested, then state:

```text
Displayed only; no task was executed.
```

Without an explicit readiness request, use only the artifact's recorded
contents. Do not reload inputs, compare current state, run validation,
reconcile, execute, mutate, or consume the artifact. Mention recorded
incompleteness, unknowns, or inputs a receiver will need to reload when
material.

## Reconcile Readiness

An explicit readiness request authorizes read-only reconciliation, not
execution.

1. Reread the complete handoff and reload its changing Authoritative Inputs.
2. Recheck material cited paths, symbols, revisions, workspaces, repository
   facts, completion claims, required assumptions, and validation claims with
   proportionate read-only evidence. Do not run validation with side effects.
3. Compare the current evidence with the recorded state. Distinguish verified
   facts, session-derived decisions, unverified claims, and relevant drift.
4. Report the resolved absolute path, material drift, blockers, and whether the
   handoff remains executable. Then wait.

Readiness never implements, mutates referenced artifacts, or weakens the
separate requirement for an explicit `run` or `execute` request.

## Execute

Execute only after the user explicitly says `run` or `execute` and identifies or
confirms the resolved handoff.

1. Reread the complete handoff and report its resolved absolute path.
2. Immediately repeat the material authoritative-input and drift checks because
   state may have changed since drafting or readiness reconciliation.
3. Continue when drift is unrelated and the requested operation remains valid;
   report relevant non-blocking drift before mutation. Stop for direction when
   drift invalidates the goal, first action, scope, authority, or a required
   assumption.
4. Treat the current prompt as the task under the explicit execution authority,
   while preserving its constraints and exclusions. Follow any applicable
   repository and operation workflows through completion.

Execution never edits, moves, renames, annotates, archives, consumes, or records
status on the handoff. It may be executed again, so never treat prior execution
as proof that its claims remain current.
