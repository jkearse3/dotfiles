# Phase Issue Format

Issue list format shared by phase verification and reconciliation.

## Issue Format

```markdown
### Issues
1. [ ] src/auth.ts:42 (bug, high): Race condition in token refresh
2. [ ] (human, medium): Login flow feels sluggish
3. [x] src/utils.ts:15 (clarity, low): Renamed ambiguous variable (resolved)
```

Number sequentially from existing issues. Do not renumber. Keep the list flat.

Review issue types are `bug`, `design`, `clarity`, `question`, and `nit`. Review severities are
`high`, `medium`, and `low`.
