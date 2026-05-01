# Reset

Reset the current goal's `00-main.md` to a blank template. Destructive — confirms before proceeding.

Read this format reference before executing this procedure:

- `${CLAUDE_SKILL_DIR}/references/templates.md`

## Steps

1. **Validate current goal**: Read `.goals/_current` symlink
   - If missing or broken: nudge — "No active goal. Want me to load or create one?"

2. **Resolve path**: Follow `.goals/_current` through to actual directory, locate `00-main.md`
   - If `00-main.md` doesn't exist: error — "No `00-main.md` found at goal destination."

3. **Confirm**: Show warning and wait for explicit approval:

   ```
   This will erase all contents of <goal-name>/00-main.md and replace with a blank template.
   This cannot be undone (except via version control). Proceed? (yes/no)
   ```

   - Only proceed on explicit "yes"
   - Any other response: abort with "Reset cancelled."

4. **Reset**: Overwrite `00-main.md` using the New Goal template from the format reference

5. **Report**: "Reset `<goal-name>/00-main.md` to blank template."

## Notes

- Only resets `00-main.md` — phase files and other supplementary files in the directory are
  untouched
- To fully reset, manually delete phase files (`NN-phase-*.md`) from the goal directory
- Symlink and directory structure are preserved
- Use version control (`jj`) to recover if needed
