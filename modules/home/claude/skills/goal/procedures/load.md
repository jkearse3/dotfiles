# Load

Load a goal.

Read these format references before executing this procedure:

- `${CLAUDE_SKILL_DIR}/references/structure.md`
- `${CLAUDE_SKILL_DIR}/references/phases.md`

## Arguments

Optional goal name or slug to load directly.

## Steps

1. **Detect branch**:
   - Run `jj-bookmark-current`
   - Slugify result: lowercase, replace `/` with `-`, strip non-alphanumeric (except `-`)
   - Empty result means trunk/no bookmark

2. **Check mismatch** (skip if argument provided):
   - If `_current` symlink exists and points to a valid goal, and branch is not empty, and no
     argument given:
     - Extract slug from `_current` target (strip `YYYY-MM-DD-HHMM-` prefix; fallback strip
       `YYYY-MM-DD-` prefix)
     - If extracted slug differs from detected branch slug:
       - Inform: "Current goal `<current-name>` doesn't match branch `<branch-name>`."
       - Ask: "Switch to matching goal, create one, or keep current?"
       - Wait for user response, then route:
         - **Switch**: go to step 3 "no argument and branch detected" path (finds matching goal by
           branch slug)
         - **Create**: read and follow `${CLAUDE_SKILL_DIR}/procedures/create.md`
         - **Keep**: go to step 6 (load current goal as-is)
       - Stop here until user responds

3. **Route by argument**:

   **If argument provided**:
   - Extract slug from each `.claude/_goals/` entry (exclude `_current`, `_config.yaml`): strip
     `YYYY-MM-DD-HHMM-` prefix first; if no match, strip `YYYY-MM-DD-` prefix
   - Find entries whose extracted slug exactly matches the argument
   - If exactly one match: go to step 5 (handle selection) with that goal
   - If multiple matches: go to step 4 (list), filtered to matching entries only
   - If no match: go to step 4 (list) with note: `No goal matching "<argument>".`

   **If no argument and branch detected (not trunk)**:
   - Extract slug from each `.claude/_goals/` entry (same method as above)
   - Find entries whose extracted slug exactly matches the branch slug
   - If exactly one match: go to step 5 (handle selection) — direct load, no list
   - If no match: offer to create — "No goal for branch `<branch-name>`. Want me to create one?"
     - Wait for user response. Stop here.
   - If multiple matches: go to step 4 (list), filtered to matches

   **If no argument and on trunk**: go to step 4 (list)

4. **List goals**: Find all entries in `.claude/_goals/` (exclude `_current`, `_config.yaml`)
   - Check each entry is valid (directory exists or symlink target exists); mark broken ones
   - Read `_current` symlink to identify current goal
   - If no goals exist: show hint and stop: "No goals found. Want me to create one?"
   - Present as text (not interactive selection — user responds naturally):

     ```
     Goals:
     1. 2024-01-15-1430-auth-refactor *
     2. 2024-01-10-fix-bug (branch match)
     3. 2024-01-08-old-thing [broken]

     Which one?
     ```

   - Annotate `*` on current goal
   - Annotate `(branch match)` on entries whose extracted slug matches the detected branch slug
   - Annotate `[broken]` on broken symlinks
   - Wait for user response — user picks by number or name
   - Stop here until user responds

5. **Handle selection**:

   **If broken symlink selected**: Error "Symlink target missing. Run `/goal load` to select
   another."

   **If existing selected**:
   - Update `_current` symlink if different from selection

6. **Load goal**:
   - Resolve `.claude/_goals/_current` through to actual directory
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

- **After compaction**: Goal was previously loaded but context was compacted
- **Stale detection**: User references prior work ("as we discussed", "the plan we made") but goal
  not loaded

When auto-loading, skip selection (steps 1-5) — use current symlink directly.
