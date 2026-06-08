# Switch

Select an objective explicitly and move to its existing jj bookmark.

## Arguments

Optional objective name or slug. Without an argument, list objectives and ask the user to choose.

## References

- `references/objective-names.md` — Slugify and Extract Objective Slug.
- `references/objective-registry.md` — registry entries, valid entries, and `_current` updates.
- `procedures/load.md` — canonical objective context loading and presentation.

## Steps

1. Find objectives.
   - List entries in `.objectives/` excluding `_current` and `_config.yaml`.
   - Check each entry is valid: directory exists or symlink target exists.
   - For each entry, keep both the full entry name and the extracted slug per
     `references/objective-names.md` § Extract Objective Slug.
   - If no objectives exist, stop: `No objectives found. Run /objective create to create one.`

2. Select objective.
   - If an argument was provided, slugify it per `references/objective-names.md` § Slugify.
   - Match an argument against either the exact objective entry name or the exact extracted
     objective slug.
   - If exactly one valid objective matches, select it.
   - If multiple objectives match, stop and list the conflicting entry names.
   - If no valid objective matches, stop: `No objective matching "<argument>".`
   - If no argument was provided, present objectives as text and wait for the user to choose by
     number, entry name, or slug:

     ```text
     Objectives:
     1. 2024-01-15-1430-auth-refactor *
     2. 2024-01-10-0930-fix-bug
     3. 2024-01-08-1200-old-thing [broken]

     Which one?
     ```

   - Mark the current objective with `*` by reading `.objectives/_current` if it exists.
   - Mark broken symlinks with `[broken]`.
   - If a broken symlink is selected, stop:
     `Objective entry <entry-name> points to a missing destination.`

3. Verify bookmark and working copy.
   - Derive the destination bookmark name from the selected objective slug.
   - Verify a jj bookmark with that exact name exists.
   - If the bookmark does not exist, stop:

     ```text
     Objective `<entry-name>` has no matching jj bookmark `<bookmark-name>`.
     `/objective switch` does not create bookmarks.
     ```

   - Verify the working copy is clean before moving to the bookmark.
   - If there are uncommitted changes, stop:

     ```text
     Working copy has uncommitted changes. Commit or discard them before `/objective switch`.
     ```

4. Switch objective.
   - Move the working copy to the existing matching jj bookmark.
   - Update `.objectives/_current` only when it points somewhere else. Point `_current` at the
     selected objective entry name, preserving `references/objective-registry.md` real-directory and
     configured symlink registry modes.

5. Load and present objective context.
   - Run `procedures/load.md` to load and present context for the now-current bookmark.
   - Do not duplicate focused-phase, continuation, or context-presentation handling in this
     procedure.

## Contracts

- `/objective switch` owns explicit non-current objective selection.
- `/objective switch` must not create missing objectives or bookmarks.
- Refuse to move bookmarks unless the working copy is clean.
- Update `_current` only when the selected objective differs from the current objective.
- Preserve objective registry compatibility for real directories, configured symlink entries, and
  `_current` updates.
