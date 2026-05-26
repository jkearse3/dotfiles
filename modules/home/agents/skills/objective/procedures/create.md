# Create

Create a new objective derived from the current branch/bookmark name.

## Arguments

Optional bookmark name. If provided, creates or moves to that bookmark.

## References

- `references/contracts.md` — file conventions, Slugify, Extract Objective Slug, invariants.
- `references/structure.md` — objective registry and symlink layout.
- `references/templates.md` — New Objective template.

## Steps

1. Resolve branch name.

   If argument provided (bookmark name):
   - Check whether the bookmark exists: `jj log -r '<arg>' --no-graph --limit 1` (suppress errors).
     - If it exists: move to it with `jj new <arg>`.
     - If not:
       - Run `jj-bookmark-current` and `jj-bookmark-default`.
       - If on a non-trunk bookmark (not empty, doesn't match default): `jj new` first (stack on top
         of current bookmark), then `jj bookmark create <arg>`.
       - If on trunk: `jj bookmark create <arg>`.
     - Verify with `jj-bookmark-current`.
   - Branch name = argument.

   If no argument:
   - Run `jj-bookmark-current` and `jj-bookmark-default`.
   - If empty or matches default branch, nudge — "On trunk. Provide a bookmark name, or want me to
     create one?"
   - Branch name = result.

2. Derive slug from the branch name via `references/contracts.md` § Slugify.

3. Generate prefix `YYYY-MM-DD-HHMM` from the current date and time (24-hour).

4. Resolve destination. Check `.objectives/_config.yaml` for `destination_pattern:`.
   - If the pattern exists: resolve token substitutions (`<year>`/`<y>`, `<month>`/`<m>`,
     `<day>`/`<d>`, `<time>`/`<t>`, `<name>`/`<n>`) and use as destination (configured mode).
   - If no config: destination is `.objectives/<prefix>-<slug>` (default mode — real directory, no
     symlink, no prompt).

5. Check for duplicates.
   - If `.objectives/<prefix>-<slug>` already exists, stop with error: "Objective `<prefix>-<slug>`
     already exists. Use `/objective load` to load it."
   - Also check whether any existing objective entry's slug (per `references/contracts.md` § Extract
     Objective Slug) matches the new slug. If a match is found, stop with error: "Objective already
     exists for this branch: `<existing-entry-name>`. Use `/objective load` to load it."

6. Create objective.

   Default mode (no `_config.yaml`):
   - Create directory: `mkdir -p ".objectives/<prefix>-<slug>"`.
   - Write `00-main.md` in the directory using the New Objective template.
   - Update `_current` symlink: `ln -sfn "<prefix>-<slug>" ".objectives/_current"`.

   Configured mode (with `_config.yaml`):
   - Create destination directory: `mkdir -p "<destination>"`.
   - Write `00-main.md` at the destination using the New Objective template.
   - Create symlink in `.objectives/`:
     `ln -s "<relative-path-to-destination>" ".objectives/<prefix>-<slug>"`.
   - Update `_current` symlink: `ln -sfn "<prefix>-<slug>" ".objectives/_current"`.

7. Load objective (auto-load after creation).
   - Resolve `.objectives/_current` through to the actual directory.
   - Read `00-main.md`.
   - Find the focused phase (marked with `*` in `## Phases`).

8. Present context.
   - Confirm creation: "Created objective `<prefix>-<slug>` for branch `<branch-name>`".
   - Show the Context section.
   - Suggest next steps: start with `/objective investigate` or `/objective spec`.

## Contracts

- Preserve the trunk nudge, duplicate-objective errors, and creation confirmation verbatim.
- Default mode writes a real directory and no symlink; configured mode writes the destination plus
  the `.objectives/` symlink.
- `_current` always points at `<prefix>-<slug>`.
