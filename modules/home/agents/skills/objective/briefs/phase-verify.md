# Phase Verify Brief

Verify working changes for a phase of the objective workflow: first code review for quality issues,
then AC validation if review is clean.

## References

- `references/contracts.md` — file conventions and § Invariants (caller-token preservation and the
  single-revision rule).

## Write Permissions

- Write the phase file at the provided path (update issues and write result summary)
- Modify entries in `## Acceptance Criteria` in `00-main.md` (AC markers and evidence notes for ACs
  assessed by this subagent; preserve existing AC text and `(human)` annotations, single edit)

## Steps

1. Load state. Read the state file at the path provided by the orchestrator:
   - `### Context` — intent.
   - `### Approach` — strategy and constraints guiding the implementation.
   - `### Tasks` — completed work.
   - `### Issues` — existing issues for dedup.

   Read the AC source file (`.objectives/_current/00-main.md`) `## Acceptance Criteria` section for
   AC text — used for AC validation in Step 6.

2. Check for changes. Run `jj diff --stat` (or `git diff --stat` if jj is unavailable). If no
   changes, stop and return the no-changes `## Result: Verify Summary` block (see Contracts). The
   exact string `No changes to verify.` is a contract consumed by
   `skills/objective/procedures/phase-iterate.md` Step 5 branch detection — do not change the
   wording without updating the caller.

3. Run code review. Build a context-enriched `/code-review` invocation from state file context and
   diff data (see Contracts § Code Review Invocation). Gather context (skip any section with no
   content):
   1. **Intent summary** — from `### Context`, a one-line summary of what is being built.
   2. **Known issues** — from `### Issues`, all open issues (`[ ]`). Keep the native format:
      `- path:line (type, severity): description`.
   3. **Language hints** — from the Step 2 diff stat, detect unique file extensions. For each, note
      the matching `language-<lang>` skill if one exists (e.g., `.go` -> `language-go`, `.ts` ->
      `language-ts`).
   4. **Branch files** — run `jj diff --from "$(jj-bookmark-previous)" --stat` to identify files
      changed in prior phases (cross-phase interaction awareness). Include under a `## Branch Files`
      section in the invocation.

   Compose the invocation (only sections with content; if none gathered, fall back to
   `/code-review jj diff --git`). Invoke the `code-review` skill via the Skill tool with the
   composed arguments, wait for completion, and collect findings.

4. Convert findings to issues. For each finding:
   1. **Check for duplicates** — scan existing issues for same file + same concern. Duplicate of an
      open issue: skip (already tracked). Duplicate of a resolved issue: reopen by changing `[x]` to
      `[ ]`.
   2. **Append new issues** to `### Issues`: `N. [ ] path:line (type, severity): description`.

   Number sequentially from existing issues (don't renumber); flat list only; types `bug`, `design`,
   `clarity`, `question`, `nit`; severity `high`, `medium`, `low`.

5. Check review gate. If new issues were created in Step 4, stop and return the review-only
   `## Result: Verify Summary` block (see Contracts). Do not proceed to AC validation — the
   orchestrator loop will dispatch implement to address the issues. If no new issues, proceed.

6. AC validation. For each AC (from `.objectives/_current/00-main.md` `## Acceptance Criteria`):
   1. **Identify relevant code** — use completed tasks to find what changed.
   2. **Read the code** — examine the implementation.
   3. **Assess satisfaction** — does this code actually fulfill the AC?
   4. **Reference existing tests** — if tests exist, cite them as supporting evidence.
   5. **Determine status**:
      - `[x]` — code satisfies AC AND you're confident (has tests, or implementation is trivial).
      - `[~]` — code appears to satisfy AC but needs verification (implement decides: tests or
        human).
      - `[!]` — previously satisfied but no longer (regression).
      - `[ ]` — not yet implemented.

   Include the determined status for each AC in the Step 9 summary.

7. AC derivation. For each AC targeted by phase tasks (identified by `(ACN, satisfy/enhance)`
   annotations in the phase file `### Tasks`):
   1. **enhance-preservation**: If all referencing tasks are `(ACN, enhance)`, preserve the existing
      AC marker and text from `00-main.md` as-is (enhancement doesn't change satisfaction status).
   2. **human-preservation**: ACs with `(human)` annotations in the phase file are never modified —
      preserve both the marker and the annotation.
   3. **fallback**: If a task is `(ACN, satisfy)` but no matching AC exists in `00-main.md`, flag it
      as a readiness issue in `### Issues` rather than silently creating one.
   4. **satisfy derivation**: For `(ACN, satisfy)` tasks with a matching AC, use the AC validation
      status from Step 6. If the AC was validated `[x]`, mark it `[x]` with evidence notes. If
      validated `[~]`, mark it `[~]` with evidence notes.

   Update `## Acceptance Criteria` in `00-main.md` in a single edit:
   - Update markers using the derived status.
   - Add evidence notes from Step 6 validation (fully qualified paths, test results).
   - Preserve existing AC text and `(human)` annotations.

8. Confirm issue persistence. Re-read the state file and confirm every new Step 4 finding has been
   appended to `### Issues` with the correct format
   (`N. [ ] path:line (type, severity): description`). If any are missing — write skipped or dedup
   decision reversed — append them now. The Step 9 summary is not a substitute for state-file
   persistence; the orchestrator loop relies on `### Issues` to dispatch follow-up work.

9. Present summary. Return the full `## Result: Verify Summary` block (see Contracts). Include AC
   derivation results (which ACs were updated, which were preserved, any readiness issues flagged).

## Contracts

### Result Blocks

Headings and fields are caller-parsed — do not rename or reorder.

No changes (Step 2):

```
## Result: Verify Summary

No changes to verify.
```

Review gate (Step 5, new issues created):

```
## Result: Verify Summary

### New Issues
- [count by severity, or "None"]

### Total Open Issues
- [count remaining [ ], or "None"]

### Recommendation
- [address high-severity issues before next cycle]
```

Full summary (Step 9):

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

### Code Review Invocation

Assemble a markdown document as the `/code-review` argument. Only include sections that have
content. If no context was gathered, fall back to `/code-review jj diff --git`.

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

### Issue Format

```markdown
### Issues
1. [ ] src/auth.ts:42 (bug, high): Race condition in token refresh
2. [ ] (human, medium): Login flow feels sluggish
3. [x] src/utils.ts:15 (clarity, low): Renamed ambiguous variable (resolved)
```

### Rules

- Code review automatically dedupes against existing issues (won't re-flag same concerns).
- Issues accumulate across cycles (audit trail).
- Review focuses on code quality; AC validation focuses on correctness and completeness.
- Validate ACs by reading code, not just running tests. Tests are supporting evidence, not the sole
  source of truth.
- State file is the single source of truth — all issues are written there.
- **Verify decides satisfaction, not verification method**: mark `[~]` when you want verification;
  implement decides if that's tests or human.
- **Confidence threshold for `[x]`**: has passing tests -> `[x]`; implementation is obvious/trivial
  -> `[x]`.
- **Use `[~]` when**: code looks correct but no tests exist and behavior isn't trivial; or uncertain
  about control flow, event handling, or framework behavior.
