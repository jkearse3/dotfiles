---
name: jj-atomize
description: Atomize jj revision into conventional commits [revision]
argument-hint: "[revision-id]"
---

Analyze revision and either describe it (if atomic) or split it into multiple atomic commits with
full jj revision descriptions.

## Arguments

```
$ARGUMENTS
```

Format: `[--single] [revision]`

- `--single`: Force single commit (skip split analysis)
- `revision`: Target revision (default: `@`)

**Validation**: Parse flags first, then revision. If extra args remain, error:

```
Error: expected [--single] [revision]
```

## Steps

1. **Verify revision** exists and has changes (fail if empty).

2. **Analyze changes**:
   - Get diff: `jj diff -r <revision>` (full) and `--stat` (summary)
   - For each file, identify:
     - What it introduces (new functions, types, exports)
     - What it uses (imports, references)
     - Type of change (conventional commits)
     - Scope (component/area affected)
   - For body content, identify:
     - Status quo or problem being solved
     - What the change does in response
     - Any breaking changes or related issues

3. **Group and order** (skip if `--single`):
   - Group files by semantic purpose (same feature + scope)
   - Build dependency graph (if B uses what A introduces → A before B)
   - **Validate feasibility**:
     - If any file appears in multiple groups → requires hunk-level split
     - Merge affected groups and note: "Grouped [X] and [Y] - splitting within [file] requires
       interactive mode"
   - Order groups:
     1. Dependencies first (hard constraint)
     2. Then by complexity: style < chore < docs < test < ci < build < refactor < perf < fix < feat
     3. Tie-breaker: fewer files first

4. **Present proposal**:

   Follow the repo's version-control rules when composing revision descriptions — type/scope
   taxonomy, subject format (72 chars, imperative mood, no period), body (status quo first, then
   change; contextual mood; domain language; wrap at 72), footer (breaking change trailer, issue
   refs).

   If atomic (1 group):

   ```
   ## Atomic

   type(scope): description

   Status quo or problem, then change in response.

   **Files**: file1.ext, file2.ext
   **Reasoning**: [why atomic, why this message]
   ```

   If needs splitting (N groups):

   ```
   ## Split into N commits

   ### 1. type(scope): description

   Status quo or problem, then change in response.

   - file.ext (+X -Y): what changed

   ### 2. type(scope): description

   Status quo or problem, then change in response.

   - file.ext (+X -Y): what changed

   **Ordering**: [why this order]
   ```

5. **Iterate** based on feedback until confirmed.

6. **Execute** using the multi-commit splitting pattern from the repo's version-control rules:
   - Compose each full revision description (subject + body + footer) per the rules above
   - Assign multi-line revision descriptions to a shell variable and pass the quoted variable to
     `-m`:

     ```bash
     desc='type(scope): description

     Status quo or problem, then change in response.'
     jj split -r <target> -m "$desc" file1 file2
     ```

   - Track `first_commit` and `target` through splits
   - Show result with `jj log -r '<first>::<last>'`
   - If original target was `@`: run `jj new` to create fresh working copy
