---
name: diff-review
description: >-
  Independently reviews stable, described finalized revisions, commit ranges,
  PRs, or branches for bugs, regressions, safety and compatibility risks,
  missing validation, stale artifacts, and maintainability issues across any
  changed artifact, and assesses explicitly declared criteria. Use when a
  finalized target is ready; not for working changes, implementation, fixes, or
  history mutation.
argument-hint:
  "review my branch | review jj diff --from main | review PR #42 against
  criteria.md"
---

# Diff Review

## Input

```
$ARGUMENTS
```

Free-form natural language. Interpret it as four distinct things:

1. **What to diff** — a runnable command, or a description to derive one from.
   Ask when the intent is clear but the target is not.
2. **Declared criteria** — stated in the request, in an artifact it references,
   or in a revision description that explicitly declares them; never inferred
   from context. Preserve exact wording and any supplied proof method. Apply
   criteria to the aggregate review target unless the request scopes them
   narrower. Criteria add to the quality review; they never replace it or end it
   early.
3. **Review context** — non-goals, known issues, and focus areas. Known issues
   never narrow investigation; focus areas raise scrutiny without narrowing it;
   a non-goal makes an absence a non-finding without excusing a defect in what
   did change. Review context never becomes criteria.
4. **Evidence constraints** — criteria or evidence questions earlier independent
   reviews settled, primary-source material the request quotes with its
   location, and evidence placed out of bounds. Do not gather excluded evidence,
   reopen located quoted material the target does not change, or re-derive a
   conclusion the request states has rested on unmoved evidence since the round
   that settled it. Evidence constraints relieve evidence-gathering, never
   scrutiny of the diff.

If excluded or unavailable evidence prevents a verdict, a criterion is
materially ambiguous or its source cannot be resolved, or a claimed settled
conclusion lacks the unmoved-evidence statement, mark only the affected item
`blocked`, name what it needs, and continue. If evidence placed out of bounds
covers changed material, do not inspect it; mark that coverage blocked and
continue only reachable review work.

The target must resolve once to immutable revision IDs, and every included
revision must have a non-empty description. Resolve every mutable diff endpoint,
including the head and comparison base, without creating or moving refs. For an
unpublished checked-out target, require an empty jj working-copy revision on top
or a clean Git worktree. If the input does not identify a target, ask for one
and stop. An unresolvable target, unfinalized work, an empty required
description, or a failed diff blocks substantive review. An empty aggregate diff
blocks only when every included revision diff is also empty.

## Principles

- Investigate plausible change-reachable defects to evidence-backed verdicts,
  with scrutiny proportional to their production, data, security, and
  compatibility impact. Stop gathering evidence once more could not alter a
  finding, criterion, or status; report unavailable evidence that still could.
- Apply governing repository patterns when they exist. Otherwise require
  concrete present-day harm rather than general best practice, and prefer the
  smallest sufficient correction.
- Review is read-only.

## Execution

**Resolve the target**, then run the diff before reviewing it:

- One revision: review it directly.
- A stack: review the aggregate delta, and check each revision's own diff
  against its description for accuracy, boundary coherence, and content the
  stack adds and later removes. Do not run every lens over each revision in
  turn: the assembled result is what the change delivers, and per-revision
  sweeps cost more than they catch.
- A fresh empty undescribed `@`: treat `@-` as the target.
- A stacked bookmark: take the aggregate base from the target's own ancestry,
  not the repository's default bookmark. `jj-bookmark-previous` resolves
  relative to `@`, so use it only after confirming the target is the current
  bookmark.
- An ambiguous merge, parent, or base: ask rather than guess.

Read every target revision's full description and treat it as author intent, not
proof:

```bash
jj log -r '<revset>' --no-graph --no-pager --template 'change_id.short() ++ " " ++ commit_id.short() ++ "\n" ++ description ++ "\n\n"'
git log --format=fuller --no-patch <range>
```

Require each description to account accurately for its revision's diff; report a
vague or mismatched one as a finding. Use what a description does say to check
the diff against the problem, constraints, excluded scope, and risks it claims.

**Inspect every changed hunk** under every concern its behavior could affect,
reading only enough enclosing or related context to settle the verdict. For
generated, vendored, minified, or pure-data files, inspect each changed hunk in
its relevant block rather than reading the full file. For generated deltas,
confirm each hunk is explained by reviewed source and inspect unexplained deltas
in depth. When a changed contract has many consumers, locate its uses, inspect
every distinct or high-risk pattern, and group mechanical repetition.

Use the cheapest authoritative evidence that settles each question; corroborate
only when behavior remains unestablished or sources conflict. Do not disassemble
or decompile binaries; use reviewed source and relevant metadata, blocking only
affected items when those cannot settle them. Gather criterion evidence in the
same pass, including material unchanged behavior, and run checks only when they
leave no persistent repository or external state. Author claims are context, not
proof; author reasoning and verification results are out of bounds in an
independent review. Carried evidence is defined under Input.

Apply only lenses reachable from changed behavior or promises:

- _Behavior and contracts_ — correctness, edge cases, ordering, concurrency,
  cleanup, trust boundaries, secrets, validation, and API, schema, config,
  workflow, platform, client, and persisted-data compatibility.
- _Operations, data, dependencies_ — complexity and resource cost, I/O, caching,
  rendering, observability, defaults, permissions, CI, deployment, portability,
  rollout and rollback, integrity, migrations, locking, dependencies, licenses,
  lockfiles, supply-chain risk, and generated consistency.
- _Validation and claims_ — important success, failure, and edge coverage,
  meaningful assertions and fixtures, and accuracy of user claims, docs,
  comments, runbooks, migration notes, examples, and references.
- _Artifact-specific concerns_ — design, coupling, and visibility; prompt
  precedence, permissions, stops, routing, results, and parser strings; UI and
  asset semantics, accessibility, integrity, responsive and theme behavior; and
  naming, structure, or dead material under governing style. Without one, report
  clarity only when a natural reading leads to the wrong action.

**Then read the changeset whole**: inconsistent patterns, incomplete refactors,
partial migrations, integration gaps, stale generated artifacts, and criterion
evidence spanning files or revisions.

**Before reporting**, recheck that each finding and criterion verdict follows
from decisive evidence, each blocker names what is missing, and coverage
accounts for the target. Do not repeat the main review.

## Result

**Filter every finding by one test: what must change?** If nothing, drop it; if
"maybe consider", investigate and make a concrete call. Report only findings
carrying a clear, actionable fix — or, for `question` and `design`, a specific
decision the reader must make. A fix that requires supporting a new use case,
consumer, platform, failure model, or compatibility promise is out of scope
unless explicitly required: investigation may be broad, but findings stay inside
what the change can reach. Skip renames that are not meaningfully clearer, and
dedupe repeated findings by file and concern, not exact line. Suppress a known
issue from Findings only when the target neither introduces nor worsens it, and
identify the existing issue in Coverage.

Report the applicable elements below, combining sections and omitting empty ones
when that makes the result shorter:

- **Status:** `pass` when the review covered the target, every declared
  criterion is satisfied, every required revision is accurately described, and
  there are no findings; `blocked` when target preflight ended the review;
  otherwise `non-pass`.
- **Coverage:** when the review reached the diff, compactly name the inspected
  paths or groups, applicable lenses, revisions checked for a stack, and
  anything unreachable or locally blocked with the missing evidence. Do not
  summarize every changed file; add an overview only when findings need it for
  orientation.
- **Criteria:** only when declared, identify each criterion unambiguously and
  mark it `satisfied`, `not satisfied`, or `blocked` with concise admissible
  evidence or a precise blocker. Use a stable ID, heading, or source location
  instead of repeating long criteria when that reference is unique. Assessment
  states whether declared outcomes hold; findings state what must change. A
  `not satisfied` criterion produces a finding only when there is a concrete
  corrective action; a `blocked` one does not unless required validation is
  absent or the change improperly claims completion.
- **Findings:** highest priority first as
  `- location (category, priority): description`, where location may be a path,
  line, range, revision, or the whole target.

**Categories:** `bug` (incorrect behavior, including unintended divergence from
its description), `safety` (security, data loss, trust boundary, operational, or
destructive-action risk), `compatibility` (broken consumer, API, schema, config,
docs, workflow, platform, or migration contract), `accuracy` (docs, comments,
prompts, generated artifacts, or examples that mislead, including stale material
after an intended behavior change), `coverage` (missing or weak tests,
validation, fixtures, or rollout checks), `design` (architectural concern or
trade-off), `clarity` (readability, naming, structure, or instruction
ambiguity), `question` (authority or intent needs a decision).

**Priority:** `high` — fix before merge. `medium` — worth addressing. `low` — a
concrete minor defect that does not block merge.
