---
name: diff-review
description: >-
  Reviews current changes, diffs, PRs, branches, or working trees as an independent quality gate;
  finds actionable bugs, regressions, safety risks, compatibility breaks, missing validation, stale
  artifacts, and maintainability issues across code, docs, config, infra, prompts, skills, and other
  changed artifacts. Use when asked to review changes or when a workflow needs independent diff
  quality review before acceptance or validation.
argument-hint: "review my branch changes | review jj diff --from main | review PR #42"
---

# Diff Review

Thorough, pedantic diff review that classifies changed artifacts, traces affected consumers and
contracts, verifies behavior or claims, and checks every file against the review lenses that apply
to code, tests, docs, config, infrastructure, migrations, dependencies, prompts, rules, skills,
assets, and mixed changes.

## Input

```
$ARGUMENTS
```

The input is free-form natural language. Interpret it to determine:

1. **What to diff**: a literal command, a description of what to review, or both. If the input
   contains a runnable command, use it directly. If it describes what to review ("my branch
   changes", "PR #42", "the last 3 commits"), determine the appropriate diff command. If the intent
   is clear but the exact diff cannot be determined (e.g., "review my changes" without enough
   context to know the base), ask for clarification rather than guessing.
2. **Additional context**: any background, known issues, review rules, artifact types, or focus
   areas included in the input. Note these for use during review.

**If the input is empty**, error with:

```
Error: describe what to review

Examples:
  review my branch changes against main
  jj diff --from main --to @
  review PR #42, focus on error handling
  git diff HEAD~3..HEAD - adding auth middleware, watch for session leaks
  git diff main..HEAD - docs, config, and migration changes need compatibility review
```

## Philosophy

- Investigate before dismissing: if something looks off, trace it. Never move on without a concrete
  verdict backed by evidence.
- Be thorough to the point of paranoia: check every edge case, trace every affected consumer or
  contract, verify every assumption. The cost of a missed production, operations, policy, or user
  workflow break exceeds the cost of a thorough review.
- Challenge design decisions: if there is a simpler way, a more robust way, or a way that better
  fits existing patterns, flag it.
- Repo patterns take precedence over general best practices. Only flag deviations when no pattern
  exists or an existing pattern is clearly problematic.
- Scope is diff quality: correctness, safety, compatibility, accuracy, design, clarity, coverage,
  testing, accessibility, operability, and maintainability across all changed artifacts.

## Execution

### Step 1: Gather Context

**Get changed files**: Run the diff. If the input described what to review rather than providing a
literal command, determine the appropriate diff command now. Get the changed file list from the
output. If the command fails, report the error and stop. If no files changed, report "no changes
found" and stop.

**Classify changed files before deep review**. Assign each changed file one or more artifact types:

- `code`: runtime source, libraries, scripts, UI components, typed models, generated source that is
  checked in for runtime use.
- `test`: unit, integration, fixture, snapshot, harness, or test utility changes.
- `docs`: README, runbook, reference, changelog, comments used as user-facing docs.
- `config`: app config, editor config, package metadata, policy, feature flags, permissions.
- `infra`: deployment, CI, containers, Nix, Terraform, orchestration, service manifests.
- `migration`: database, data backfill, schema, serialized data, compatibility transition.
- `dependency`: lockfiles, dependency manifests, vendored code, version constraints.
- `generated`: compiled output, generated code, generated docs, snapshots, or codegen products.
- `prompt/rule/skill`: AI prompts, agent rules, skills, command briefs, instruction files.
- `asset`: images, fonts, media, icons, design tokens, binary artifacts.
- `mixed`: files that combine multiple artifact concerns or whose role is ambiguous.

Generated output may be skipped when it is clearly derived and the source delta is sufficient.
Review lockfiles and generated artifacts when their deltas reveal dependency, schema, API,
compatibility, or release risk. When in doubt, review.

**Establish repo patterns** from changed artifact types:

- Sample similar files, functions, docs, config blocks, workflows, prompts, or manifests.
- Check neighboring artifacts for naming, structure, error handling, policy, schema, and formatting
  patterns.
- Search for project guidelines (`**/ARCHITECTURE.md`, `**/*style*.md`, `**/CONTRIBUTING.md`, agent
  rules, workflow docs, release docs, etc.).

### Step 2: Deep File Analysis

For each changed file, perform the full investigation and review before moving to the next file. Do
not skim. Exhaust every applicable category against this file's changes before proceeding.

**Investigation (mandatory for every file):**

1. **Load diff** for this file. Get the diff scoped to this specific file: derive a file-scoped
   command, filter the full diff output, or use any method that isolates this file's changes.

2. **Load full file**. Diffs alone hide surrounding context that determines correctness, accuracy,
   and compatibility.

3. **Confirm artifact classification**. Record whether the file is code, test, docs, config, infra,
   migration, dependency, generated, prompt/rule/skill, asset, or mixed. Apply all relevant review
   lenses for mixed files.

4. **Trace affected consumers and contracts** when the changes affect behavior, interfaces, policy,
   documented usage, data, or generated output. Search for consumers of changed APIs, commands,
   config keys, env vars, data shapes, paths, schemas, prompt behavior, docs promises, CI jobs,
   deployment contracts, migration assumptions, asset references, and generated artifacts. Determine
   whether existing consumers still work correctly. Skip only for purely cosmetic changes,
   mechanical renames with complete find-replace evidence, or formatting-only deltas.

5. **Verify behavior and claims**. Do not assume how a function, library, tool, command, config key,
   policy, schema, migration, prompt, or documented workflow behaves. If a change relies on specific
   behavior, ordering, defaults, error semantics, concurrency safety, rendering, deployment
   behavior, or generated output, confirm it by reading the source, docs, tests, manifests, or
   generated delta.

**Review every applicable category against this file's changes:**

_Code Correctness & Safety_

- Error handling: all paths covered? errors informative?
- Inputs: validated, sanitized, normalized, and trusted only at correct boundaries?
- Edge cases: empty, null, missing, boundary, partial, duplicate, malformed, or out-of-order data?
- State combinations: all input permutations and lifecycle states handled?
- Logic: correct algorithm, ordering, off-by-one, time zone, locale, encoding, or precision
  behavior?
- Secrets: any hardcoded, logged, exposed, over-permissioned, or committed?
- Resource management: leaks, cleanup, cancellation, rollback, retries, idempotency?
- Concurrency: race conditions, stale closures, deadlocks, reentrancy, shared mutable state?

_Performance & Operability_

- Algorithmic complexity: O(n^2) where O(n) works? unnecessary iteration?
- Allocations and I/O: avoidable copies, conversions, network calls, filesystem work, or round
  trips?
- Caching and batching: repeated expensive lookups that should be shared or batched?
- UI rendering: unnecessary re-renders, layout thrash, large bundle impact?
- Operations: observability, rollout safety, failure modes, alert noise, logging quality?

_Design & Architecture_

- Separation of concerns: responsibility clear across code, config, docs, and automation?
- Abstractions: appropriate level? over- or under-engineered?
- Dependencies: coupling minimized? direction correct? version or platform constraints compatible?
- Patterns: consistent with repo conventions? deviation justified?
- Security: trust boundaries, permissions, policy, sandbox, and supply-chain risks respected?
- Visibility: narrowest possible? public symbols, config keys, docs promises, or workflow contracts
  created without consumers?
- Data integrity: schema changes backwards-compatible? migration safe? serialized data evolution
  handled? Flag as `question` when intent is unclear.

_Tests & Coverage_

- Coverage: key behavior, policy, config, docs examples, migrations, prompts, and workflows tested
  or otherwise validated?
- Missing cases: obvious success, failure, edge, rollback, compatibility, accessibility, and
  security cases not covered?
- Quality: assertions meaningful? tests verify behavior, not implementation? brittle snapshots or
  fixtures? tests that pass for the wrong reason?
- Test artifacts: fixtures, snapshots, and helpers updated consistently with the behavior change?

_Docs & Accuracy_

- User-facing claims: commands, examples, options, defaults, paths, screenshots, and limitations are
  accurate after the diff?
- Internal docs: comments, docstrings, runbooks, ADRs, and changelogs align with code/config
  behavior?
- Completeness: docs cover migration steps, compatibility notes, operational impact, or user action
  where required?
- Staleness: removed behavior, renamed fields, changed outputs, or old screenshots still referenced?

_Config, Infrastructure & Automation_

- Config semantics: default values, precedence, env vars, paths, permissions, and feature flags are
  correct and documented where needed?
- CI/CD: jobs, caches, artifacts, matrix entries, secrets, and triggers still match project intent?
- Deployment: rollout order, rollback, health checks, resource limits, and platform constraints
  safe?
- Tooling: formatter, linter, generator, package manager, and shell behavior portable enough for the
  repo's supported environments?

_Data, Migrations & Dependencies_

- Migrations: reversible or safely forward-only? ordering, locking, batching, backfill, and downtime
  implications understood?
- Compatibility: existing persisted data, clients, APIs, generated files, and external integrations
  remain compatible or have clear migration paths?
- Dependencies: lockfile deltas match manifest intent; licenses, supply-chain risk, transitive
  changes, peer constraints, and runtime platform support are acceptable?
- Generated artifacts: generated deltas are consistent with source changes and do not hide API,
  schema, or release risk.

_Prompts, Rules & Skills_

- Instruction behavior: prompts and rules produce the intended agent behavior without conflicting
  with higher-priority instructions or existing workflows?
- Scope boundaries: write permissions, tool permissions, stop conditions, routing fields, and
  contracts are explicit and safe?
- Consumer contracts: command names, skill names, state-file fields, result blocks, and
  parser-facing strings stay compatible where required?
- Ambiguity: unclear precedence, missing examples, or open-ended instructions that could cause
  unsafe or inconsistent execution?

_Assets & Accessibility_

- Accessibility: semantic HTML, ARIA, focus, contrast, reduced motion, alt text, media captions, and
  keyboard behavior where applicable?
- Asset integrity: file format, dimensions, compression, licensing, cache busting, and references
  are correct?
- Visual behavior: responsive layout, density, localization, and theme interactions still work?

_Clarity & Maintainability_

- Naming: intent clear and consistent across code, docs, config, prompts, and artifacts?
- Structure: focused functions, files, sections, manifests, and workflows?
- Dead or stale material: unused code, config keys, docs, assets, snapshots, imports, assignments,
  or generated output?
- Comments and prose: explain why, not what. Flag noisy restatements, banners, stale rationale, and
  missing rationale on non-obvious behavior.

Record all findings for this file, then move to the next.

### Step 3: Cross-File Synthesis

After all per-file analysis, review findings across the full changeset:

- Inconsistent patterns between files, docs, tests, config, infra, prompts, or assets.
- Incomplete refactors, renamed concepts, updated commands, changed config keys, or partial
  migrations.
- Integration gaps: mismatched interfaces, broken contracts, missing docs, invalid examples, stale
  generated artifacts, incompatible lockfiles, or CI/deployment drift.
- Emergent concerns invisible in per-file analysis.

### Step 4: Synthesize Overview

Before self-challenge, synthesize a concise overview from context already gathered in Steps 1-3. No
additional tool calls. This step is pure synthesis.

1. **Concise overview**: Briefly explain what this changeset does overall, the key design decisions,
   and how the changed artifacts relate to each other. Keep it short, but let the changeset size and
   artifact mix determine the exact shape.

2. **Per-file breakdown**: For each changed file, state:
   - The file's artifact type and role in the system.
   - What changed and why it matters.

This overview will appear before findings in the written block to orient the reader.

### Step 5: Self-Challenge

Before writing findings, stop and re-examine:

- Re-read each finding: is the evidence concrete or assumed?
- Re-read each dismissal: did you actually investigate, or move on too fast?
- Look at the changeset fresh: what would a skeptical reviewer flag that you did not?
- Check whether any non-code artifact weakened a code, test, docs, config, infra, data, dependency,
  prompt, or asset contract.
- Promote or add findings discovered in this step.

### Step 6: Dedupe and Write

**Dedupe** (if known issues were provided in the input):

- Remove findings that match known issues: same file and same concern.
- Line numbers may shift; match on semantic similarity, not exact line.

**Write structured findings** (new issues only)

## Findings Format

**Before reporting a finding, ask:** "What should the author do?"

- If the answer is "nothing" or "accept as-is", do not report it.
- If the answer is "maybe consider...", investigate first, make a concrete call.
- Only report findings with clear, actionable fixes.

If deep analysis and self-challenge produce zero findings, write the `### Overview` section followed
by an empty `### Findings` section with a single line stating no issues were found. The overview
already summarizes what was investigated; do not repeat that information.

Write findings as a structured list, preceded by the overview.

```markdown
### Overview

<Concise overview of what the changeset does overall, key design decisions, and how the changed
artifacts relate to each other.>

- `path/file.go` (code) - <file's role in the system>; <what changed and why it matters>
- `docs/guide.md` (docs) - <file's role in the system>; <what changed and why it matters>

### Findings

- path/file.go:42 (bug, high): Race condition in session map access
- docs/guide.md:18 (accuracy, medium): Documented flag name does not match the CLI parser
- deploy/app.yaml:15 (compatibility, high): Removed env var still consumed by production job
```

Format: `- path:line (category, priority): description`

**Categories:**

- `bug`: likely incorrect behavior.
- `safety`: security, data loss, trust-boundary, operational, or destructive-action risk.
- `compatibility`: broken consumer, API, schema, config, docs, workflow, platform, or migration
  contract.
- `accuracy`: docs, comments, prompts, generated artifacts, examples, or metadata are wrong or
  misleading.
- `coverage`: missing or weak tests, validation, examples, fixtures, generated artifacts, or rollout
  checks for important behavior.
- `design`: architectural concern or trade-off.
- `clarity`: readability, naming, structure, or instruction ambiguity.
- `question`: something unclear, worth discussing.
- `nit`: minor issue, trivial to fix.

**Priority:**

- `high`: critical, should fix before merge.
- `medium`: important, worth addressing.
- `low`: minor, fix if touching that artifact anyway.

**What to skip:**

- "Consider whether..." without concrete concern.
- Renaming suggestions that are not meaningfully clearer.
- Findings where the action is "nothing".
