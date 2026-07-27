# Load

Load the objective that matches the current jj bookmark.

## Arguments

No arguments. Explicit non-current selection is handled by
`/objective switch [name]`.

## References

- `references/objective-names.md` — Slugify and Extract Objective Slug.
- `references/objective-registry.md` — registry entries, valid entries, and
  `_current` updates.

## Steps

1. Resolve current bookmark.
   - Run `jj-bookmark-current`.
   - Run `jj-bookmark-default`.
   - If the current bookmark is empty or equals the default bookmark, stop:

     ```text
     No objective loaded: `/objective load` requires a non-default jj bookmark.
     Create one with `/objective create`, or select an existing objective with `/objective switch`.
     ```

   - Derive the current bookmark slug via `references/objective-names.md` §
     Slugify.

2. Match objective by bookmark slug.
   - Scan `.objectives/` entries only as needed to compare objective slugs.
     Exclude `_current` and `_config.yaml`.
   - Extract each objective slug per `references/objective-names.md` § Extract
     Objective Slug.
   - Find entries whose extracted slug exactly matches the current bookmark
     slug.
   - If no entries match, stop:

     ```text
     No objective matches bookmark `<bookmark-name>`.
     Run `/objective create` to create an objective for this bookmark.
     ```

   - If multiple entries match, stop and list the conflicting entry names:

     ```text
     Multiple objectives match bookmark `<bookmark-name>`:
     - <entry-name>
     - <entry-name>

     Resolve the duplicate objectives before loading.
     ```

   - Do not list unrelated objectives and do not ask the user to choose an
     unrelated objective.

3. Select matching objective.
   - Check the matched entry is valid: directory exists or symlink target
     exists.
   - If the matched entry is a broken symlink, stop:
     `Objective entry <entry-name> points to a missing destination.`
   - Update `.objectives/_current` only when it points somewhere else. Point
     `_current` at the matched objective entry name, preserving
     `references/objective-registry.md` real-directory and configured symlink
     registry modes.

4. Load objective context.
   - Resolve `.objectives/_current` through the objective entry to the actual
     directory.
   - Read `00-main.md` first.
   - Find focused phases marked with `[focus]` in `## Phases`.
   - If exactly one focused phase exists, read `references/phase-index.md`, then
     resolve and read only that phase file via § Phase Resolution.
   - If the focused phase contains `### Continuation`, read it as the primary
     resume state. Do not modify or clear it while loading.
   - If zero or multiple focused phases exist, do not read phase files while
     loading. Report the phase focus issue in the presented context.

5. Present context.
   - Show Context, Research summary, and the Phases list.
   - If a focused phase exists and contains `### Continuation`: show Status,
     Source, Route, Summary, Clear when, and any Payload before pending tasks.
     Present this continuation as the next resume instruction after load or
     compaction.
   - If a focused phase exists: show the phase's approach and pending tasks.
   - Suggest next steps based on state (informational, don't ask interactively):
     - No phases yet: suggest starting research or creating the first phase.
     - Research incomplete: highlight questions/assumptions.
     - Phase in progress: highlight pending tasks.

## Auto-load Triggers

Invoke this procedure proactively when:

- After compaction: the objective was previously loaded but context was
  compacted.
- Stale detection: the user references prior work ("as we discussed", "the plan
  we made") but the objective is not loaded.

When auto-loading, follow steps 1-4 without interactive selection. The current
bookmark is the authority: if `.objectives/_current` points at a different
objective than the current bookmark, update `_current` after exactly one
objective entry matches the bookmark slug. Do not use stale `_current` state as
a fallback for trunk/default/no bookmark or no-match cases.

## Contracts

- `/objective load <name>` is not supported. Use `/objective switch [name]` for
  explicit non-current selection.
- Normal load and auto-load share bookmark-first matching where their behavior
  overlaps.
- Update `_current` only when the bookmark-matched objective differs from the
  current objective.
- Preserve objective registry compatibility for real directories, configured
  symlink entries, and `_current` updates.
- Do not modify objective files.
