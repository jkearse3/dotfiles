# Auto-Scope Dispatch

Shared auto-scope dispatch mechanics for objective phase callers.

## Dispatch

Use caller-provided `objective_dir`, `P`, `NN`, and phase-file path when already computed.
Otherwise, read `references/phase-file-inputs.md` and compute them per § Compute Phase-File Inputs.

Dispatch a subagent with:

```text
Read the bundled skill resource `briefs/phase-scope.md` and execute the instructions within it.

objective_dir: <absolute path to objective directory>
P: <phase number>
NN: <sequence number, zero-padded>
Phase file: <absolute path to phase file>
```

Callers with refinement loops reuse the same `objective_dir`, `P`, `NN`, and phase-file path for
each refinement round so the subagent overwrites the same file in place. Append caller feedback to
the dispatch prompt without restating prior draft content; the brief reads the existing phase file
for that context:

```text
User feedback:
<verbatim user feedback>

Produce a revised proposal that addresses the feedback. Overwrite the phase file at the
provided path.
```

Handle results:

- No work remaining: report the procedure-specific no-work message and stop.
- Readiness issues: surface them and stop.
- Phase proposal: the subagent has written the phase file at the computed path; read it if the
  caller needs to present proposal contents.

Default Phase proposal acceptance is automatic: add the linked entry for the provided or computed
`P`, `NN`, and phase file to `## Phases` in `00-main.md`, move focus to it, then re-read
`00-main.md` before continuing. Callers may override this, consistent with the "Preserve approval
gates" invariant. `iterate` and `auto-iterate` use default auto-accept; `phase-scope` instead
presents the proposal and waits for approval before accepting.
