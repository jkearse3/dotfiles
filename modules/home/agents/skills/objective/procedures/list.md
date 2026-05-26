# List

List all objectives in the current repository.

## Steps

1. **Find objectives**: List entries in `.objectives/` (exclude `_current`, `_config.yaml`)
   - If none: "No objectives found."
   - Sort by name (which sorts chronologically due to date prefix)
   - Check each entry is valid (directory exists or symlink target exists)

2. **Get current**: Read `.objectives/_current` symlink target (if exists)

3. **Display**:

   ```
   Objectives:
   * 2024-01-15-1430-auth-refactor
     2024-01-10-fix-bug
     2024-01-08-old-thing [broken]

   Use /objective load to switch, /objective create to create.
   ```

   - Show entry name (and symlink target path if entry is a symlink)
   - Mark current with `*`
   - Mark broken entries with `[broken]`
   - Most recent first
