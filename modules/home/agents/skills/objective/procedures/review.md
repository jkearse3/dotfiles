# Review

Autonomous review pipeline over current branch changes. Captures `REVIEW:` comments from code, runs
code review, merges findings, and creates cleanup phases. Dispatched as a subagent for isolated
execution.

Can be run at any point — not tied to phase completion. Useful for self-review after committing a
phase, general cleanup passes, or pre-PR review.

## Execution

Dispatch the review as a subagent with prompt:

```
Read the file at ~/.claude/skills/objective/procedures/review.md and follow the "Branch Review Pipeline" section.

Context: This is an autonomous branch-level review (not a per-phase inner-loop review). The pipeline
is in this file. Per-phase inner-loop verify is handled inline by `phase-iterate`.
```

Wait for the subagent to return its structured result. Present the summary to the user:

- Phases created (count and names)
- Concern counts by source (human REVIEW comments vs. code review findings)
- Out-of-scope concerns flagged (count, if any)
- Suggest: `/objective phase-iterate` to execute

## Branch Review Pipeline

This section documents the full pipeline for reference. The subagent executes it autonomously.

### Step 1: Load format references

Read these files before proceeding — they define phase file structure and atomicity constraints:

- `~/.claude/skills/objective/references/phases.md`
- `~/.claude/skills/objective/references/templates.md`

### Step 2: Load state

- Read `.objectives/_current/00-main.md`
- If no objective: nudge — "No active objective. Want me to load or create one?"

### Step 3: Load branch context

Run `jj diff --from "$(jj-bookmark-previous)" --stat` to get the list of changed files with line
counts. This defines the review scope.

### Step 4: Capture REVIEW comments

Grep the entire repository for the multi-language REVIEW pattern:

```
(//|#|--|/\*|\*|<!--)\s*REVIEW:\s*(.+)$
```

This covers: Go/JS/TS/Rust/C (`//`), Nix/Python/Shell/YAML (`#`), Lua/SQL (`--`), CSS (`/*`/`*`),
HTML/XML (`<!--`).

For each match, record:

- File path
- Line number
- Description (capture group 2, then trim trailing `\s*-->` or `\s*\*/` from HTML/XML/CSS comment
  closers)

**Multi-line comments**: If a `REVIEW:` line is found, read forward until a line matching
`(//|#|--|/\*|\*|<!--)\s*/REVIEW` is found. Concatenate all intermediate lines as the description.
The `/REVIEW` terminator is part of the block.

**Scope tagging**: Cross-reference each captured comment's file path against the branch diff stat
from Step 3. Tag each comment as `in-scope` (file is in the branch diff) or `out-of-scope` (file is
not in the branch diff — pre-existing concern the user noticed while working).

If no matches, proceed with an empty list.

### Step 5: Remove REVIEW comments

For each captured REVIEW comment, remove it from the source file:

- **Single-line**: Delete the `REVIEW:` line
- **Multi-line**: Delete from the `REVIEW:` line through the `/REVIEW` terminator (inclusive)

Adjacent non-REVIEW comments must not be affected. This must happen before the code review runs so
the reviewer sees clean code.

### Step 6: Run code review

Invoke the `code-review` skill via the Skill tool with `branch` as the argument. Collect structured
findings.

### Step 7: Merge concerns

Combine human REVIEW comments and code-review findings into a single concern list. Each entry has:

- File path
- Line number
- Description
- Source: `human` (from REVIEW comments) or `review` (from code review)
- Scope: `in-scope` or `out-of-scope` (human comments only; code review findings are always
  in-scope)

No dedup — keep both when overlapping. Human and automated perspectives are both valuable.

### Step 8: Early exit

If zero concerns (no REVIEW comments captured AND code review returned no findings): report "No
concerns found" and stop cleanly.

### Step 9: Group into phases

Separate concerns by scope first, then cluster within each scope.

**In-scope concerns**: Cluster into coherent phases. Each phase is a single commit of related
changes. Grouping criteria:

- Same module/area of code
- Same type of concern (e.g., all naming fixes, all error handling)
- Logical dependency (fix X before Y makes sense)

If only one coherent group: create a single phase.

**Out-of-scope concerns**: Group into a separate phase named `Review M: Pre-existing concerns`.
These are issues the user flagged in files outside the branch diff. They get their own phase so they
don't mix with branch-specific cleanup. If no out-of-scope concerns, skip this group.

### Step 10: Write phases

For each group, create a phase file and update `00-main.md` using the New Phase template from the
format reference:

- Determine next phase number: highest existing phase number in `## Phases` index + 1
- Determine next sequence number: scan objective directory for highest `NN-` prefix + 1
- Determine review number: search existing phases for `Review N` pattern, next = highest + 1
- Create phase file `NN-phase-P-review-M.md`:

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

- Add linked index entry to `## Phases` in `00-main.md`:
  ```markdown
  P. [ ] [Review M: <description>](./NN-phase-P-review-M.md)
  ```

Focus the first created phase (`*` in index) if no phase is currently focused.

### Step 11: Report

- Phases created (count and names)
- Concern counts by source (human REVIEW comments vs. code review findings)
- Out-of-scope concerns flagged (count, if any)
- Suggest: `/objective phase-iterate` to execute

## REVIEW Comment Convention

**Single-line** (no end marker needed):

```
# REVIEW: short concern about this code
```

**Multi-line** (explicit `/REVIEW` terminator):

```
# REVIEW: longer concern that needs
# multiple lines to explain the issue
# and suggest a direction
# /REVIEW
```

## Notes

- Dispatched as a subagent for autonomous execution.
- REVIEW comment removal happens before code review — reviewer sees clean code.
- Multiple review sessions accumulate — each creates new phases with incrementing review numbers.
- REVIEW comments in files outside the branch diff are captured as `out-of-scope` and grouped into a
  separate "Pre-existing concerns" phase.
- Inner loop (review step within Phase Iterate) is unchanged — keeps its structured findings to
  issues pipeline for working-copy scope.
