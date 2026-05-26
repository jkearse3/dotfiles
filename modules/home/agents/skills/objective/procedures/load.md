# Load

Load an objective.

Read these format references before executing this procedure:

- `references/structure.md`
- `references/phases.md`

## Arguments

Optional objective name or slug to load directly.

## Steps

1. **Detect branch**:
   - Run `jj-bookmark-current`
   - Slugify result: lowercase, replace `/` with `-`, strip non-alphanumeric (except `-`)
   - Empty result means trunk/no bookmark

2. **Check mismatch** (skip if argument provided):
   - If `_current` symlink exists and points to a valid objective, and branch is not empty, and no
     argument given:
     - Extract slug from `_current` target (strip `YYYY-MM-DD-HHMM-` prefix; fallback strip
       `YYYY-MM-DD-` prefix)
     - If extracted slug differs from detected branch slug:
       - Inform: "Current objective `<current-name>` doesn't match branch `<branch-name>`."
       - Ask: "Switch to matching objective, create one, or keep current?"
       - Wait for user response, then route:
         - **Switch**: go to step 3 "no argument and branch detected" path (finds matching objective
           by branch slug)
         - **Create**: read and follow `procedures/create.md`
         - **Keep**: go to step 6 (load current objective as-is)
       - Stop here until user responds

3. **Route by argument**:

   **If argument provided**:
   - Extract slug from each `.objectives/` entry (exclude `_current`, `_config.yaml`): strip
     `YYYY-MM-DD-HHMM-` prefix first; if no match, strip `YYYY-MM-DD-` prefix
   - Find entries whose extracted slug exactly matches the argument
   - If exactly one match: go to step 5 (handle selection) with that objective
   - If multiple matches: go to step 4 (list), filtered to matching entries only
   - If no match: go to step 4 (list) with note: `No objective matching "<argument>".`

   **If no argument and branch detected (not trunk)**:
   - Extract slug from each `.objectives/` entry (same method as above)
   - Find entries whose extracted slug exactly matches the branch slug
   - If exactly one match: go to step 5 (handle selection) — direct load, no list
   - If no match: offer to create — "No objective for branch `<branch-name>`. Want me to create
     one?"
     - Wait for user response. Stop here.
   - If multiple matches: go to step 4 (list), filtered to matches

   **If no argument and on trunk**: go to step 4 (list)

4. **List objectives**: Find all entries in `.objectives/` (exclude `_current`, `_config.yaml`)
   - Check each entry is valid (directory exists or symlink target exists); mark broken ones
   - Read `_current` symlink to identify current objective
   - If no objectives exist: show hint and stop: "No objectives found. Want me to create one?"
   - Present as text (not interactive selection — user responds naturally):

     ```
     Objectives:
     1. 2024-01-15-1430-auth-refactor *
     2. 2024-01-10-fix-bug (branch match)
     3. 2024-01-08-old-thing [broken]

     Which one?
     ```

   - Annotate `*` on current objective
   - Annotate `(branch match)` on entries whose extracted slug matches the detected branch slug
   - Annotate `[broken]` on broken symlinks
   - Wait for user response — user picks by number or name
   - Stop here until user responds

5. **Handle selection**:

   **If broken symlink selected**: Error "Symlink target missing. Run `/objective load` to select
   another."

   **If existing selected**:
   - Update `_current` symlink if different from selection

6. **Load objective**:
   - Resolve `.objectives/_current` through to actual directory
   - Read `00-main.md` (index file: context, research, ACs, approach, phases index)
   - Find focused phase (marked with `*` in `## Phases`)
   - If focused phase has a linked file, read it; otherwise read the inline section (Phase
     Resolution)

7. **Present context**:
   - Show Context, Research summary, Phases list
   - If focused phase exists: show phase's approach and pending tasks
   - Suggest next steps based on state (informational, don't ask interactively):
     - No phases yet: suggest starting research or creating first phase
     - Research incomplete: highlight questions/assumptions
     - Phase in progress: highlight pending tasks

## Auto-load Triggers

Invoke this procedure proactively when:

- **After compaction**: Objective was previously loaded but context was compacted
- **Stale detection**: User references prior work ("as we discussed", "the plan we made") but
  objective not loaded

When auto-loading, skip selection (steps 1-5) — use current symlink directly.
