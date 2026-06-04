# Branch Review

Caller-visible conventions for autonomous branch-level review phases.

## Autonomous Branch Review Conventions

Branch-level autonomous review uses these caller-visible conventions.

Report fields:

- Phases created (count and names).
- Concern counts by source (human REVIEW comments vs. code review findings).
- Out-of-scope concerns flagged (count, if any).
- Suggest: `/objective phase-iterate` to execute.

Phase numbering and file naming are computed via `references/templates.md` § Compute phase-file
inputs, with two review-specific values:

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

- **L<line>**: Concern description (source)

### Tasks
1. [ ] Task description (ACN, satisfy/enhance) or (IN)

### Issues
```

Add a linked entry to `## Phases` in `00-main.md` per `references/phases.md` Phase Index — never
renumber existing phases:

```markdown
P. [ ] [Review M: <description>](./NN-phase-P-review-M.md)
```

Preserve verbatim: the `No concerns found` early-exit string, the `Review M: Pre-existing concerns`
phase name, the `NN-phase-P-review-M.md` filename, the phase-file template, the index-entry
template, the `human`/`review` source tags, the `in-scope`/`out-of-scope` scope tags, and the report
fields.
