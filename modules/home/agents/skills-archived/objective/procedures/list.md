# List

List all objectives in the current repository.

## References

- `references/objective-registry.md` — registry entries and valid-entry
  detection.

## Steps

1. Find objectives.
   - List entries in `.objectives/` excluding `_current` and `_config.yaml`.
   - Sort by name, most recent first.
   - Check whether each entry is valid: directory exists or symlink target
     exists.
   - Stop if none: `No objectives found.`

2. Get current.
   - Read `.objectives/_current` symlink target if it exists.

3. Display objectives.

   ```
   Objectives:
   * 2024-01-15-1430-auth-refactor
     2024-01-10-fix-bug
     2024-01-08-old-thing [broken]

   Use /objective switch to switch, /objective create to create.
   ```

   - Show entry name.
   - Include symlink target path when the entry is a symlink.
   - Mark current with `*`.
   - Mark broken entries with `[broken]`.

## Contracts

- Do not modify objective files.
- Do not update `.objectives/_current`.
