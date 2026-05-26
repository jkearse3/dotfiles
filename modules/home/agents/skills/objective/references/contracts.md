# Contracts

Shared instructions for objective procedures, briefs, and references.

## File Conventions

Use this structure where applicable:

1. `# Name`
2. One-sentence purpose.
3. `## Arguments` for user-provided arguments or flags.
4. `## References` for imported instructions.
5. `## Steps` for ordered execution.
6. `## Contracts` for exact outputs, write boundaries, gates, and invariants.

`## References` are normative. Before executing a file, read every listed reference. Follow named
sections from references instead of restating them locally.

## Shared Operations

### Slugify

Lowercase; replace `/` and whitespace with `-`; strip non-alphanumeric characters except `-`.

Collapsing whitespace to `-` is intentional, aligning with `references/structure.md` ("hyphens for
spaces"). Slug inputs are jj bookmark names, which rarely contain whitespace, so the practical
effect is negligible.

### Extract Objective Slug

Strip `YYYY-MM-DD-HHMM-`; if absent, strip `YYYY-MM-DD-`.

### Load Current Objective

Resolve `.objectives/_current` to the active objective directory, then read `00-main.md`.

Stop with this nudge if no valid objective is active:

```text
No active objective. Want me to load or create one?
```

### Auto-scope Dispatch

Compute phase-file inputs per `references/templates.md`, then dispatch a subagent with:

```text
Read the file at ~/.claude/skills/objective/briefs/phase-scope.md and execute the instructions within it.

objective_dir: <absolute path to objective directory>
P: <phase number>
NN: <sequence number, zero-padded>
Phase file: <absolute path to phase file>
```

Handle results:

- No work remaining: report the procedure-specific no-work message and stop.
- Readiness issues: surface them and stop.
- Phase proposal: write the linked phase index entry and focus it.

The Phase proposal handler is a default callers may override, consistent with the "Preserve approval
gates" invariant. `phase-iterate` and `phase-interrogate` auto-accept the proposal; `phase-scope`
instead presents it and waits for approval before accepting.

## Invariants

- Preserve exact result tokens and strings consumed by callers.
- Preserve approval gates; do not turn user-approved steps into automatic writes.
- Preserve subagent write boundaries.
- Preserve AC numbering and marker semantics.
- Preserve phase numbering and focus semantics.
- Preserve the single-revision invariant: no `jj commit`, `jj new`, or `jj split` inside
  implement/verify loops; the orchestrator owns revision lifecycle.
