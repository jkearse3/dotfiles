# Create

Create a new objective derived from the current branch/bookmark name.

Read these format references before executing this procedure:

- `references/structure.md`
- `references/templates.md`

## Arguments

Optional bookmark name. If provided, creates or moves to that bookmark.

## Steps

1. **Resolve branch name**:

   **If argument provided** (bookmark name):
   - Check if bookmark already exists: `jj log -r '<arg>' --no-graph --limit 1` (suppress errors)
     - If exists: move to it with `jj new <arg>`
     - If not:
       - Run `jj-bookmark-current` and `jj-bookmark-default`
       - If on a non-trunk bookmark (not empty, doesn't match default): `jj new` first (stack on top
         of current bookmark), then `jj bookmark create <arg>`
       - If on trunk: `jj bookmark create <arg>`
     - Verify with `jj-bookmark-current`
   - Branch name = argument

   **If no argument**:
   - Run `jj-bookmark-current` and `jj-bookmark-default`
   - If empty or matches default branch: nudge — "On trunk. Provide a bookmark name, or want me to
     create one?"
   - Branch name = result

2. **Slugify branch name**: lowercase, replace `/` with `-`, strip non-alphanumeric (except `-`)

3. **Generate prefix**: `YYYY-MM-DD-HHMM` from current date and time (24-hour)

4. **Resolve destination**:
   - Check `.objectives/_config.yaml` for `destination_pattern:`
     - If pattern exists: resolve token substitutions (`<year>`/`<y>`, `<month>`/`<m>`,
       `<day>`/`<d>`, `<time>`/`<t>`, `<name>`/`<n>`), use as destination (configured mode)
     - If no config: destination is `.objectives/<prefix>-<slug>` (default mode — real directory, no
       symlink, no prompt)

5. **Check for duplicates**: If `.objectives/<prefix>-<slug>` already exists, stop with error:
   "Objective `<prefix>-<slug>` already exists. Use `/objective load` to load it."

   Also check if any existing objective entry's extracted slug matches the new slug (strip
   `YYYY-MM-DD-HHMM-` prefix first; if no match, strip `YYYY-MM-DD-` prefix). If match found, stop
   with error: "Objective already exists for this branch: `<existing-entry-name>`. Use
   `/objective load` to load it."

6. **Create objective**:

   **Default mode** (no `_config.yaml`):
   - Create directory: `mkdir -p ".objectives/<prefix>-<slug>"`
   - Write `00-main.md` in the directory using the New Objective template from the format reference
   - Update `_current` symlink: `ln -sfn "<prefix>-<slug>" ".objectives/_current"`

   **Configured mode** (with `_config.yaml`):
   - Create destination directory: `mkdir -p "<destination>"`
   - Write `00-main.md` at destination using the New Objective template from the format reference
   - Create symlink in `.objectives/`:
     `ln -s "<relative-path-to-destination>" ".objectives/<prefix>-<slug>"`
   - Update `_current` symlink: `ln -sfn "<prefix>-<slug>" ".objectives/_current"`

7. **Load objective** (auto-load after creation):
   - Resolve `.objectives/_current` through to actual directory
   - Read `00-main.md`
   - Find focused phase (marked with `*` in `## Phases`)

8. **Present context**:
   - Confirm creation: "Created objective `<prefix>-<slug>` for branch `<branch-name>`"
   - Show Context section
   - Suggest next steps: start with `/objective investigate` or `/objective spec`
