# Rename

Rename the current objective. Two modes:

- No argument: sync — rename the symlink to match the current branch.
- With argument: full rename — rename bookmark, symlink, and destination directory.

## Arguments

Optional new name. If provided, performs a full rename. If omitted, syncs the symlink to the current
branch.

## References

- `references/current-objective.md` — § Load Current Objective for the active objective gate.
- `references/objective-names.md` — Slugify and Extract Objective Slug.
- `references/objective-registry.md` — registry modes and `_current` updates.

## Steps

1. Validate the current objective per `references/current-objective.md` § Load Current Objective
   (stops with the no-active-objective nudge if missing or broken).

2. Extract current symlink info.
   - Read the `_current` symlink target name (e.g. `2024-01-15-1430-auth-refactor`).
   - Extract the timestamp prefix (`YYYY-MM-DD-HHMM-`) and the current slug from the remainder, per
     `references/objective-names.md` § Extract Objective Slug.
   - Read the symlink's target path (the destination it points to).

3. Derive the new slug via `references/objective-names.md` § Slugify.

   If argument provided: slugify the argument. This is the new slug.

   If no argument:
   - Run `jj-bookmark-current` and `jj-bookmark-default`.
   - If empty or matches the default branch: error — "On trunk. Cannot rename."
   - Slugify the branch name. This is the new slug.

4. Check if already matching. If the current slug equals the new slug:
   - If argument provided: stop — "Objective already uses name `<new-slug>`."
   - If no argument: stop — "Objective already matches branch `<branch-name>`."

5. Check for conflicts.
   - If `.objectives/<prefix>-<new-slug>` already exists, error: "Objective `<prefix>-<new-slug>`
     already exists. Cannot rename."
   - Also check whether any other existing objective symlink's slug (per
     `references/objective-names.md` § Extract Objective Slug) matches the new slug. If a match is
     found, error: "Objective already exists for this branch: `<existing-symlink-name>`. Cannot
     rename."

6. Update destination (argument mode only). If no argument, skip this step.
   - Read `.objectives/_config.yaml` for `destination_pattern:`.
   - Resolve the pattern with the preserved timestamp tokens and the new slug. The `<name>`/`<n>`
     token uses the new slug; date/time tokens use the values from the existing timestamp prefix.
   - Move the destination directory: `mv <old-destination> <new-destination>`.
     - `<old-destination>` is the resolved path the current symlink points to.
     - `<new-destination>` is the resolved path with the new slug.
     - If old and new destinations are the same (the pattern doesn't include `<name>`), skip.

7. Update symlinks.
   - Remove the old symlink: `rm .objectives/<old-name>`.
   - Create the new symlink: `ln -s "<target>" ".objectives/<prefix>-<new-slug>"`. The target is the
     new destination (relative path) if moved in step 6, otherwise the same target as before.
   - Update `_current`: `ln -sfn "<prefix>-<new-slug>" ".objectives/_current"`.

8. Rename bookmark (argument mode only). If no argument, skip this step.
   - Get the current bookmark: `jj-bookmark-current`.
   - Get the default branch: `jj-bookmark-default`.
   - If not empty and not the default branch: `jj bookmark rename <current-bookmark> <new-slug>`.
   - If on trunk (empty or default): skip the bookmark rename (no bookmark to rename).

9. Report.

   If argument provided:

   ```
   Renamed: <old-name> → <prefix>-<new-slug>
   Bookmark: <old-bookmark> → <new-slug>
   Destination: <old-destination> → <new-destination>
   ```

   Omit the Bookmark line if no bookmark was renamed. Omit the Destination line if the destination
   is unchanged.

   If no argument:

   ```
   Synced: <old-name> → <prefix>-<new-slug>
   ```

## Contracts

- Preserve the trunk error, conflict errors, "already matches" stops, and both report blocks
  verbatim.
- Preserve the original timestamp prefix in both modes.
- Sync mode renames only the symlink; the destination directory is unchanged.
- Full rename is local only — it does not push or delete remote branches. If the bookmark was
  already pushed, the user must manually sync remotes:
  `jj git push --bookmark <new> && jj git push --bookmark <old> --deleted`.
- Relative overflow file links survive destination renames because they move with the directory.
