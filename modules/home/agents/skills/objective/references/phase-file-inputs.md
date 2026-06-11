# Phase File Inputs

Phase-file input computation shared by auto-scope callers.

## Compute Phase-File Inputs

Resolve these before dispatching the scoping subagent:

- Resolve `objective_dir`: absolute path of `.objectives/_current` (resolve the symlink).
- Compute `P`: highest phase number in `## Phases` index + 1.
- Compute `NN`: highest `NN-` prefix in `objective_dir` + 1 (zero-padded to two digits).
- Build absolute path: `<objective_dir>/NN-phase-P.md`.

Use these values to identify the phase file and compose the linked index entry in `00-main.md`. The
consuming procedure or brief owns phase-file content writes and any phase template references.

Add a linked index entry in `00-main.md` under `## Phases`:

```markdown
P. [ ] [Phase Name](./NN-phase-P.md) *
```

Move `*` from the previously focused phase to the new entry.

## Contracts

- `00-main.md` remains the objective index.
- Phase files contain only the phase content; registration happens in `00-main.md`.
- Phase-file input computation owns names and index-entry shape only.
