---
name: code-review
description: Thorough staff-level code review with file-by-file findings
argument-hint: "review my branch changes | review jj diff --from main | review PR #42 with focus on error handling"
---

# Code Review

Thorough, pedantic code review that traces callers, verifies behavior, and checks every file against
correctness, performance, design, clarity, testing, and accessibility.

## Input

```
$ARGUMENTS
```

The input is free-form natural language. Interpret it to determine:

1. **What to diff** — a literal command, a description of what to review, or both. If the input
   contains a runnable command, use it directly. If it describes what to review ("my branch
   changes", "PR #42", "the last 3 commits"), determine the appropriate diff command. If the intent
   is clear but the exact diff cannot be determined (e.g., "review my changes" without enough
   context to know the base), ask for clarification rather than guessing.
2. **Additional context** — any background, known issues, review rules, or focus areas included in
   the input. Note these for use during review.

**If the input is empty**, error with:

```
Error: describe what to review

Examples:
  review my branch changes against main
  jj diff --from main --to @
  review PR #42, focus on error handling
  git diff HEAD~3..HEAD — adding auth middleware, watch for session leaks
  git diff main..HEAD — we already know about the race condition in auth.go
```

## Philosophy

- Investigate before dismissing — if something looks off, trace it. Never move on without a concrete
  verdict backed by evidence
- Be thorough to the point of paranoia — check every edge case, trace every caller, verify every
  assumption. The cost of a missed bug in production far exceeds the cost of a thorough review
- Challenge design decisions — if there's a simpler way, a more robust way, or a way that better
  fits existing patterns, flag it
- Codebase patterns take precedence over general best practices; only flag deviations when no
  pattern exists or an existing pattern is clearly problematic
- Scope is implementation quality — code correctness, design, clarity, and testing

## Execution

### Step 1: Gather Context

**Get changed files**: Run the diff. If the input described what to review rather than providing a
literal command, determine the appropriate diff command now. Get the changed file list from the
output. If the command fails, report the error and stop. If no files changed, report "no changes
found" and stop. Skip clearly generated files (lock files, compiled output, codegen with
generated-by headers) — they aren't authored code. When in doubt, review.

**Establish codebase patterns** from code and docs:

- Sample similar files/functions to see established conventions
- Check neighboring code for naming, error handling, structure patterns
- Search for project guidelines (`**/ARCHITECTURE.md`, `**/*style*.md`, etc.)

### Step 2: Deep File Analysis

For each changed file, perform the full investigation and review before moving to the next file. Do
not skim — exhaust every category against this file's changes before proceeding.

**Investigation (mandatory for every file):**

1. **Load diff** for this file. Get the diff scoped to this specific file — derive a file-scoped
   command, filter the full diff output, or use any method that isolates this file's changes.

2. **Load full file** — diffs alone hide surrounding context that determines correctness.

3. **Trace callers and consumers** when the changes affect behavior — modified signatures, changed
   logic or control flow, altered return values, or new error conditions. Search the codebase for
   usages and determine whether existing callers still work correctly. Skip for cosmetic changes
   (renames with find-replace, comment edits, formatting).

4. **Verify behavior claims** — don't assume how a function, library, or API works. If a change
   relies on specific behavior (ordering, error semantics, concurrency safety), confirm it by
   reading the source or docs.

**Review every category against this file's changes:**

_Correctness & Safety_

- Error handling — all paths covered? errors informative?
- Inputs — validated? sanitized?
- Edge cases — empty, null, boundary conditions?
- State combinations — all input permutations handled?
- Logic — correct algorithm? off-by-one?
- Secrets — any hardcoded or exposed?
- Resource management — leaks possible?
- Concurrency — race conditions? deadlocks?
- Idempotency — safe to retry? partial failure leave bad state?

_Performance_

- Algorithmic complexity — O(n^2) where O(n) works? unnecessary iteration?
- Allocations — avoidable object creation, copies, or conversions?
- Caching — repeated expensive lookups that could be cached?
- Data access — N+1 queries? missing batching? unnecessary round trips?
- UI rendering — unnecessary re-renders, missing memoization?

_Design & Architecture_

- Separation of concerns — is responsibility clear?
- Abstractions — appropriate level? over/under-engineered?
- Dependencies — coupling minimized? direction correct?
- Patterns — consistent with codebase? deviation justified?
- Security — trust boundaries respected?
- Visibility — narrowest possible? public symbols without external callers?
- Data integrity — schema changes backwards-compatible? migration safe? serialized data evolution
  handled? flag as `question` when intent is unclear

_Clarity & Maintainability_

- Naming — intent clear? consistent?
- Functions — focused? appropriate length?
- Dead code — unused paths, imports, assignments?
- Comments — explain "why", not "what"; flag noise: restating code, dividers, banners, section
  markers; flag missing rationale on non-obvious logic. If a "what" comment seems needed, the code
  itself may not be clear enough
- Stale docs — comments, docstrings, or docs now wrong after the change?
- Field docs — all struct/object fields documented? no naked fields?

_Testing_

- Coverage — key paths tested?
- Missing — obvious cases not covered?
- Quality — assertions meaningful? testing behavior, not implementation? tests that pass for the
  wrong reason? brittle tests?

_Accessibility_ (UI components only, skip if not applicable)

- Semantic HTML — button vs div? proper disabled/readonly attributes?
- ARIA — labels, roles, live regions where needed?
- Keyboard — focusable? tab order sensible?

Record all findings for this file, then move to the next.

### Step 3: Cross-File Synthesis

After all per-file analysis, review findings across the full changeset:

- Inconsistent patterns between files (error handling, naming conventions, structure)
- Incomplete refactors (renamed in one file but not others, partial migrations)
- Integration gaps (mismatched interfaces, broken contracts between modules)
- Emergent concerns invisible in per-file analysis

### Step 4: Synthesize Overview

Before self-challenge, synthesize a concise overview from context already gathered in Steps 1-3. No
additional tool calls — this step is pure synthesis.

1. **Narrative** (2-3 sentences): What does this changeset do overall? What are the key design
   decisions? How do the changed files relate to each other?

2. **Per-file breakdown**: For each changed file, state:
   - The file's role in the system (from Step 2's full-file reads and caller tracing)
   - What changed and why it matters

This overview will appear before findings in the written block to orient the reader.

### Step 5: Self-Challenge

Before writing findings, stop and re-examine:

- Re-read each finding — is the evidence concrete or assumed?
- Re-read each dismissal — did you actually investigate, or move on too fast?
- Look at the changeset fresh — what would a skeptical reviewer flag that you didn't?
- Promote or add findings discovered in this step

### Step 6: Dedupe and Write

**Dedupe** (if known issues were provided in the input):

- Remove findings that match known issues (same file + same concern)
- Line numbers may shift; match on semantic similarity, not exact line

**Write structured findings** (new issues only)

## Findings Format

**Before reporting a finding, ask:** "What should the author do?"

- If the answer is "nothing" or "accept as-is" → don't report it
- If the answer is "maybe consider..." → investigate first, make a concrete call
- Only report findings with clear, actionable fixes

If deep analysis and self-challenge produce zero findings, write the `### Overview` section followed
by an empty `### Findings` section with a single line stating no issues were found. The overview
already summarizes what was investigated — do not repeat that information.

Write findings as a structured list, preceded by the overview.

```markdown
### Overview

<Narrative: 2-3 sentences describing what the changeset does overall, key design decisions,
and how the changed files relate to each other.>

- `path/file.go` — <file's role in the system>; <what changed and why it matters>
- `path/other.go` — <file's role in the system>; <what changed and why it matters>

### Findings

- path/file.go:42 (bug, high): Race condition in session map access
- path/file.go:78 (clarity, medium): `handleAuth` does validation too - rename or split
- path/other.go:15 (design, medium): Tight coupling to external service
```

Format: `- path:line (category, priority): description`

**Categories:**

- `bug` - Likely incorrect behavior
- `design` - Architectural concern or trade-off
- `clarity` - Readability, naming, structure
- `question` - Something unclear, worth discussing
- `nit` - Minor issue, trivial to fix

**Priority:**

- `high` - Critical, should fix before merge
- `medium` - Important, worth addressing
- `low` - Minor, fix if touching that code anyway

**What to skip:**

- "Consider whether..." without concrete concern
- Renaming suggestions that aren't meaningfully clearer
- Findings where the action is "nothing"
