# Phase File Inputs

Phase-file input computation shared by auto-scope callers.

## References

- `references/phase-file-template.md` — New Phase.

## Compute Phase-File Inputs

Resolve these before dispatching the scoping subagent:

- Resolve `objective_dir`: absolute path of `.objectives/_current` (resolve the symlink).
- Compute `P`: highest phase number in `## Phases` index + 1.
- Compute `NN`: highest `NN-` prefix in `objective_dir` + 1 (zero-padded to two digits).
- Build absolute path: `<objective_dir>/NN-phase-P.md`.

Use these values to write the phase file and register it in `00-main.md`.

1. Create `NN-phase-P.md` at the computed absolute path using `references/phase-file-template.md` §
   New Phase.
2. Add a linked index entry in `00-main.md` under `## Phases`.

```markdown
P. [ ] [Phase Name](./NN-phase-P.md) *
```

3. Move `*` from the previously focused phase to the new entry.

## Contracts

- `00-main.md` remains the objective index.
- Phase files contain only the phase content; registration happens in `00-main.md`.
- Phase-file input computation is shared by all auto-scope callers.
