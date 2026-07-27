# Objective Registry

Objective registry layout and current-objective pointer rules.

## Registry Entries

`.objectives/` is the objective registry. Entries are either real directories
(default) or symlinks to destination paths (configured). `_current` always
points to the active entry.

Exclude `_current` and `_config.yaml` when listing objective entries.

## Default Mode

Without `.objectives/_config.yaml`, objective entries are real directories in
`.objectives/`. Point `.objectives/_current` at the selected entry name.

## Configured Mode

With `.objectives/_config.yaml`, objective entries are symlinks in
`.objectives/` pointing to destination directories. Files live at the
destination from the start.

Symlink targets are relative paths. Point `.objectives/_current` at the selected
objective entry name, not at the entry destination.

## Valid Entries

An objective entry is valid when it is a directory or a symlink whose target
exists. A broken symlink is an invalid entry and should be reported as broken or
stopped on, depending on the caller.
