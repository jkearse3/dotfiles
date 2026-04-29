# Rename

Rename the current goal. Two modes:

- **No argument**: Sync — rename symlink to match current branch (existing behavior).
- **With argument**: Full rename — rename bookmark, symlink, and destination directory.

Read this format reference before executing this procedure:

- `${CLAUDE_SKILL_DIR}/references/structure.md`

## Arguments

Optional new name. If provided, performs a full rename. If omitted, syncs symlink to current branch.

## Steps

1. **Validate current goal**: Read `.claude/_goals/_current` symlink
   - If missing or broken: nudge — "No active goal. Want me to load or create one?"

2. **Extract current symlink info**:
   - Read `_current` symlink target name (e.g. `2024-01-15-1430-auth-refactor`)
   - Extract timestamp prefix: `YYYY-MM-DD-HHMM-` first; fallback `YYYY-MM-DD-`
   - Extract current slug from the remainder
   - Read the symlink's target path (the destination it points to)

3. **Derive new slug**:

   **If argument provided**:
   - Slugify argument: lowercase, replace `/` with `-`, strip non-alphanumeric (except `-`). This is
     the new slug.

   **If no argument**:
   - Run `jj-bookmark-current` and `jj-bookmark-default`
   - If empty or matches default branch: error — "On trunk. Cannot rename."
   - Slugify branch name: lowercase, replace `/` with `-`, strip non-alphanumeric (except `-`). This
     is the new slug.

4. **Check if already matching**: If current slug equals new slug:

   **If argument provided**: stop — "Goal already uses name `<new-slug>`."

   **If no argument**: stop — "Goal already matches branch `<branch-name>`."

5. **Check for conflicts**: If `.claude/_goals/<prefix>-<new-slug>` already exists, error: "Goal
   `<prefix>-<new-slug>` already exists. Cannot rename."

   Also check if any other existing goal symlink's extracted slug matches the new slug (strip
   `YYYY-MM-DD-HHMM-` prefix first; if no match, strip `YYYY-MM-DD-` prefix). If match found, error:
   "Goal already exists for this branch: `<existing-symlink-name>`. Cannot rename."

6. **Update destination** (argument mode only):

   **If argument provided**:
   - Read `.claude/_goals/_config.yaml` for `destination_pattern:`
   - Resolve pattern with the preserved timestamp tokens and new slug
   - The `<name>`/`<n>` token uses the new slug; date/time tokens use the values from the existing
     timestamp prefix
   - Move destination directory: `mv <old-destination> <new-destination>`
     - `<old-destination>` is the resolved path the current symlink points to
     - `<new-destination>` is the resolved path with new slug
     - If old and new destinations are the same (pattern doesn't include `<name>`), skip

   **If no argument**: skip this step.

7. **Update symlinks**:
   - Remove old symlink: `rm .claude/_goals/<old-name>`
   - Create new symlink: `ln -s "<target>" ".claude/_goals/<prefix>-<new-slug>"`
     - Target is the new destination (relative path) if moved in step 6, otherwise the same target
       as before
   - Update `_current`: `ln -sfn "<prefix>-<new-slug>" ".claude/_goals/_current"`

8. **Rename bookmark** (argument mode only):

   **If argument provided**:
   - Get current bookmark: `jj-bookmark-current`
   - Get default branch: `jj-bookmark-default`
   - If not empty and not default branch: `jj bookmark rename <current-bookmark> <new-slug>`
   - If on trunk (empty or default): skip bookmark rename (no bookmark to rename)

   **If no argument**: skip this step.

9. **Report**:

   **If argument provided**:

   ```
   Renamed: <old-name> → <prefix>-<new-slug>
   Bookmark: <old-bookmark> → <new-slug>
   Destination: <old-destination> → <new-destination>
   ```

   Omit Bookmark line if no bookmark was renamed. Omit Destination line if destination unchanged.

   **If no argument**:

   ```
   Synced: <old-name> → <prefix>-<new-slug>
   ```

## Notes

- Sync mode only renames the symlink — destination directory is unchanged
- Full rename is local only — does not push or delete remote branches
- If the bookmark was already pushed, user must manually sync remotes:
  `jj git push --bookmark <new> && jj git push --bookmark <old> --deleted`
- Preserves the original timestamp prefix in both modes
- Relative overflow file links survive destination renames since they move with the directory
