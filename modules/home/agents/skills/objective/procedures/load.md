# Load

Load an objective.

## Arguments

Optional objective name or slug to load directly.

## References

- `references/contracts.md` — file conventions, Slugify, Extract Objective Slug, invariants.
- `references/structure.md` — objective registry and symlink layout.
- `references/phases.md` — phase resolution.

## Steps

1. Detect branch.
   - Run `jj-bookmark-current`.
   - Derive a slug from the result via `references/contracts.md` § Slugify.
   - An empty result means trunk/no bookmark.

2. Check mismatch (skip if argument provided).
   - If `_current` exists and points to a valid objective, the branch is not empty, and no argument
     was given:
     - Extract the slug from the `_current` target per `references/contracts.md` § Extract Objective
       Slug.
     - If the extracted slug differs from the detected branch slug:
       - Inform: "Current objective `<current-name>` doesn't match branch `<branch-name>`."
       - Ask: "Switch to matching objective, create one, or keep current?"
       - Wait for the user response, then route:
         - Switch: go to step 3 "no argument and branch detected" path (finds the matching objective
           by branch slug).
         - Create: read and follow `procedures/create.md`.
         - Keep: go to step 6 (load the current objective as-is).
       - Stop here until the user responds.

3. Route by argument.

   If argument provided:
   - Extract the slug from each `.objectives/` entry (exclude `_current`, `_config.yaml`) per
     `references/contracts.md` § Extract Objective Slug.
   - Find entries whose extracted slug exactly matches the argument.
   - If exactly one match: go to step 5 (handle selection) with that objective.
   - If multiple matches: go to step 4 (list), filtered to matching entries only.
   - If no match: go to step 4 (list) with the note `No objective matching "<argument>".`

   If no argument and branch detected (not trunk):
   - Extract the slug from each `.objectives/` entry (same method as above).
   - Find entries whose extracted slug exactly matches the branch slug.
   - If exactly one match: go to step 5 (handle selection) — direct load, no list.
   - If no match: offer to create — "No objective for branch `<branch-name>`. Want me to create
     one?" Wait for the user response. Stop here.
   - If multiple matches: go to step 4 (list), filtered to matches.

   If no argument and on trunk: go to step 4 (list).

4. List objectives. Find all entries in `.objectives/` (exclude `_current`, `_config.yaml`).
   - Check each entry is valid (directory exists or symlink target exists); mark broken ones.
   - Read the `_current` symlink to identify the current objective.
   - If no objectives exist, show the hint and stop: "No objectives found. Want me to create one?"
   - Present as text (not interactive selection — the user responds naturally):

     ```
     Objectives:
     1. 2024-01-15-1430-auth-refactor *
     2. 2024-01-10-fix-bug (branch match)
     3. 2024-01-08-old-thing [broken]

     Which one?
     ```

   - Annotate `*` on the current objective.
   - Annotate `(branch match)` on entries whose extracted slug matches the detected branch slug.
   - Annotate `[broken]` on broken symlinks.
   - Wait for the user response — the user picks by number or name. Stop here until the user
     responds.

5. Handle selection.
   - If a broken symlink was selected: error "Symlink target missing. Run `/objective load` to
     select another."
   - If an existing objective was selected: update the `_current` symlink if different from the
     selection.

6. Load objective.
   - Resolve `.objectives/_current` through to the actual directory.
   - Read `00-main.md` (index file: context, research, ACs, approach, phases index).
   - Find the focused phase (marked with `*` in `## Phases`).
   - If the focused phase has a linked file, read it; otherwise read the inline section (Phase
     Resolution).
   - If the focused phase contains `### Continuation`, read it as the primary resume state. Do not
     modify or clear it while loading.

7. Present context.
   - Show Context, Research summary, and the Phases list.
   - If a focused phase exists and contains `### Continuation`: show Status, Source, Route, Summary,
     Clear when, and any Payload before pending tasks. Present this continuation as the next resume
     instruction after load or compaction.
   - If a focused phase exists: show the phase's approach and pending tasks.
   - Suggest next steps based on state (informational, don't ask interactively):
     - No phases yet: suggest starting research or creating the first phase.
     - Research incomplete: highlight questions/assumptions.
     - Phase in progress: highlight pending tasks.

## Auto-load Triggers

Invoke this procedure proactively when:

- After compaction: the objective was previously loaded but context was compacted.
- Stale detection: the user references prior work ("as we discussed", "the plan we made") but the
  objective is not loaded.

When auto-loading, skip selection (steps 1-5) — use the current symlink directly.

## Contracts

- Preserve the mismatch prompt, the listing block, branch-match annotations, the no-match create
  offers, and auto-load triggers verbatim.
- Update `_current` only when the selection differs from the current objective.
- Do not modify objective files.
