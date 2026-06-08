# Phase Verify Brief

Verify working changes for a phase of the objective workflow: first code review for quality issues,
then AC validation if review is clean.

## References

- `references/phase-subagent-state.md` — § Load Phase Subagent State.
- `references/workflow-invariants.md` — § Invariants (caller-token preservation, write boundaries,
  and the single-revision rule).
- `references/ac-markers.md` — AC states and evidence.
- `references/ac-validation.md` — § AC Validation And Derivation.
- `references/phase-issue-format.md` — issue format.
- `references/phase-verify-results.md` — caller-parsed verify result blocks.

## Write Permissions

- Write the phase file at the provided path (update issues and write result summary)
- Modify entries in `## Acceptance Criteria` in `00-main.md` (AC markers and evidence notes for ACs
  assessed by this subagent; preserve existing AC text and `(human)` annotations, single edit)

## Steps

1. Load state. Apply `references/phase-subagent-state.md` § Load Phase Subagent State. Use AC text
   for AC validation in Step 6.

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

   Apply `references/phase-issue-format.md` § Issue Format.

5. Check review gate. If new issues were created in Step 4, stop and return the review-only
   `## Result: Verify Summary` block (see Contracts). Do not proceed to AC validation — the
   orchestrator loop will dispatch implement to address the issues. If no new issues, proceed.

6. AC validation. Apply `references/ac-validation.md` § AC Validation And Derivation to inspect
   changed code, cite supporting tests, select AC statuses, and prepare evidence for each AC from
   `.objectives/_current/00-main.md` `## Acceptance Criteria`.

7. AC derivation. Apply `references/ac-validation.md` § AC Validation And Derivation for ACs
   targeted by `(ACN, satisfy/enhance)` phase task annotations. Preserve enhancement-only ACs,
   preserve human-marked ACs, flag missing satisfy targets as readiness issues in `### Issues`, and
   update `## Acceptance Criteria` in `00-main.md` in a single edit.

8. Confirm issue persistence. Re-read the state file and confirm every new Step 4 finding has been
   appended to `### Issues` with the correct format
   (`N. [ ] path:line (type, severity): description`). If any are missing — write skipped or dedup
   decision reversed — append them now. The Step 9 summary is not a substitute for state-file
   persistence; the orchestrator loop relies on `### Issues` to dispatch follow-up work.

9. Present summary. Return the full `## Result: Verify Summary` block (see Contracts). Include AC
   derivation results (which ACs were updated, which were preserved, any readiness issues flagged).

## Contracts

### Result Blocks

Apply `references/phase-verify-results.md` § Verify Summary Result Blocks.

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

Apply `references/phase-issue-format.md` § Issue Format.

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
