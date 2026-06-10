# Branch Review

Caller-visible conventions for autonomous branch-level review phases.

## Autonomous Branch Review Conventions

Branch-level autonomous review uses these caller-visible conventions.

Report fields:

- Phases created (count and names).
- Actionable findings grouped (count).
- Findings filtered out as non-actionable, duplicate, or outside branch scope (count, if any).
- Suggest: `/objective iterate` to execute.

Phase numbering and file naming are computed via `references/phase-file-inputs.md` § Compute
Phase-File Inputs, with two review-specific values:

- Review number `M`: search existing phases for the `Review N` pattern; next `M` = highest + 1.
- Filename is `NN-phase-P-review-M.md` (not the base `NN-phase-P.md`).

Write `NN-phase-P-review-M.md` using the New Phase template, overriding the heading and
`### Approach` with review content:

```markdown
## Phase P: Review M: <description>

### Context

### Approach

Address review feedback from autonomous review of branch changes.

#### path/file.ext

- **L<line>**: Concern description

### Tasks
1. [ ] Task description satisfying `references/phase-task-boundary.md` § Phase Task Boundary (ACN, satisfy/enhance) or (IN)

### Issues
```

Add a linked entry to `## Phases` in `00-main.md` per `references/phase-index.md` Phase Index —
never renumber existing phases:

```markdown
P. [ ] [Review M: <description>](./NN-phase-P-review-M.md)
```

Preserve verbatim: the `No concerns found` early-exit string, the `NN-phase-P-review-M.md` filename,
the phase-file template, the index-entry template, and the report fields.
