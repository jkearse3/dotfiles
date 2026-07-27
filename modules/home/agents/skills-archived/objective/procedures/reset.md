# Reset

Reset the current objective's `00-main.md` to a blank template. Destructive —
confirms before proceeding.

## References

- `references/current-objective.md` — § Load Current Objective for the active
  objective gate.
- `references/objective-template.md` — New Objective template.

## Steps

1. Validate the current objective per `references/current-objective.md` § Load
   Current Objective (stops with the no-active-objective nudge if missing or
   broken).

2. Resolve the path. Follow `.objectives/_current` through to the actual
   directory and locate `00-main.md`.
   - If `00-main.md` doesn't exist: error — "No `00-main.md` found at objective
     destination."

3. Confirm. Show the warning and wait for explicit approval:

   ```
   This will erase all contents of <objective-name>/00-main.md and replace with a blank template.
   This cannot be undone (except via version control). Proceed? (yes/no)
   ```

   - Only proceed on an explicit "yes".
   - Any other response: abort with "Reset cancelled."

4. Reset. Overwrite `00-main.md` using the New Objective template.

5. Report: "Reset `<objective-name>/00-main.md` to blank template."

## Contracts

- Preserve the destructive-confirm block, the abort message, and the report
  verbatim.
- Proceed only on an explicit "yes".
- Reset only `00-main.md` — phase files (`NN-phase-*.md`) and other
  supplementary files in the directory are untouched. To fully reset, the user
  manually deletes the phase files.
- The symlink and directory structure are preserved. Recovery is via version
  control (`jj`).
