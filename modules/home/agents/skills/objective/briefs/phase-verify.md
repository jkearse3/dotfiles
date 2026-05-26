# Phase Verify Brief

## Instructions

You are verifying working changes for a phase of the objective workflow: first code review for
quality issues, then AC validation if review is clean.

### Step 1: Load State

Read the state file at the path provided by the orchestrator.

Read these sections:

- `### Context` -- understand the intent
- `### Approach` -- strategy and constraints guiding the implementation
- `### Tasks` -- see completed work
- `### Issues` -- existing issues for dedup

Read the AC source file (`.objectives/_current/00-main.md`) `## Acceptance Criteria` section for AC
text -- used for AC validation in Step 6.

### Step 2: Check for Changes

Run `jj diff --stat` (or `git diff --stat` if jj is unavailable).

- If no changes: stop and return the summary below. The exact string `No changes to verify.` is a
  contract consumed by `skills/objective/procedures/phase-iterate.md` Step 5 branch detection — do
  not change the wording without updating the caller.

  ```
  ## Result: Verify Summary

  No changes to verify.
  ```

### Step 3: Run Code Review

Build a context-enriched `/code-review` invocation from state file context and diff data.

**Gather context** (skip any section that has no content):

1. **Intent summary** -- from `### Context`, extract a one-line summary of what is being built.
2. **Known issues** -- from `### Issues`, collect all open issues (`[ ]`). Keep the native format:
   `- path:line (type, severity): description`
3. **Language hints** -- from the diff stat output (Step 2), detect unique file extensions. For each
   extension, note the matching `language-<lang>` skill if one exists (e.g., `.go` -> `language-go`,
   `.ts` -> `language-ts`).
4. **Branch files** -- run `jj diff --from "$(jj-bookmark-previous)" --stat` to identify files
   changed in prior phases. This gives awareness of cross-phase interaction points for the code
   review. Include the output under a `## Branch Files` section in the invocation.

**Compose invocation** -- assemble a markdown document as the `/code-review` argument. Only include
sections that have content. If no context was gathered, fall back to `/code-review jj diff --git`.

````
/code-review
```
jj diff --git
```

## Intent

<one-line intent summary>

## Known Issues

<open issues in native format>
- path:line (type, severity): description

## Branch Files

<output of jj diff --from "$(jj-bookmark-previous)" --stat>

## Rules

- Invoke `language-<lang>` skill for <lang> files
````

Invoke the `code-review` skill via the Skill tool with the composed arguments. Wait for completion.
Collect findings.

### Step 4: Convert Findings to Issues

For each finding from code review:

1. **Check for duplicates** -- scan existing issues in the state file for same file + same concern
   - If duplicate of open issue: skip (already tracked)
   - If duplicate of resolved issue: reopen existing by changing `[x]` to `[ ]`
2. **Append new issues** to `### Issues` in the state file:
   ```markdown
   N. [ ] path:line (type, severity): description
   ```

Rules:

- Number sequentially from existing issues (don't renumber)
- Flat list only -- no groupings or sub-headers
- Types: `bug`, `design`, `clarity`, `question`, `nit`
- Severity: `high`, `medium`, `low`

### Step 5: Check Review Gate

If new issues were created in Step 4, stop and return a review-only summary:

```
## Result: Verify Summary

### New Issues
- [count by severity, or "None"]

### Total Open Issues
- [count remaining [ ], or "None"]

### Recommendation
- [address high-severity issues before next cycle]
```

Do not proceed to AC validation. The orchestrator loop will dispatch implement to address the
issues.

If no new issues were found, proceed to Step 6.

### Step 6: AC Validation

For each AC (from `.objectives/_current/00-main.md` `## Acceptance Criteria`):

1. **Identify relevant code**: use completed tasks to find what was changed
2. **Read the code**: examine the implementation
3. **Assess satisfaction**: does this code actually fulfill the AC?
4. **Reference existing tests**: if tests exist, cite them as supporting evidence
5. **Determine status**:
   - `[x]` -- code satisfies AC AND you're confident (has tests, or implementation is trivial)
   - `[~]` -- code appears to satisfy AC but needs verification (implement will decide: tests or
     human)
   - `[!]` -- previously satisfied but no longer (regression)
   - `[ ]` -- not yet implemented

Include the determined status for each AC in the summary output (Step 8).

### Step 7: Confirm Issue Persistence

Before returning, re-read the state file and confirm that every new finding produced in Step 4 has
been appended to `### Issues` with the correct format
(`N. [ ] path:line (type, severity): description`). If any are missing — whether due to a write
skipped or a dedup decision reversed — append them now. The summary in Step 8 is not a substitute
for state-file persistence; the orchestrator loop relies on `### Issues` to dispatch follow-up work.

### Step 8: Present Summary

```
## Result: Verify Summary

### Review
- Issues: [count new issues, or "Clean -- no issues found"]

### Validated
- [list of ACs now [x], or "None"]

### Needs Verification
- [list of [~] ACs with explanation, or "None"]

### Regressions
- [list of [!] ACs with explanation, or "None"]

### Not Implemented
- [list of remaining [ ] ACs, or "None"]
```

## Issue Format

```markdown
### Issues
1. [ ] src/auth.ts:42 (bug, high): Race condition in token refresh
2. [ ] (human, medium): Login flow feels sluggish
3. [x] src/utils.ts:15 (clarity, low): Renamed ambiguous variable (resolved)
```

## Rules

- Code review automatically dedupes against existing issues (won't re-flag same concerns).
- Issues accumulate across cycles (audit trail).
- Review focuses on code quality; AC validation focuses on correctness and completeness.
- Validate ACs by reading code, not just running tests.
- Tests are supporting evidence, not the sole source of truth.
- State file is the single source of truth -- all issues are written there.
- **Verify decides satisfaction, not verification method**: mark `[~]` when you want verification;
  implement decides if that's tests or human.
- **Confidence threshold for `[x]`**:
  - Has passing tests -> `[x]`
  - Implementation is obvious/trivial -> `[x]`
- **Use `[~]` when**:
  - Code looks correct but no tests exist and behavior isn't trivial
  - Uncertain about control flow, event handling, or framework behavior
