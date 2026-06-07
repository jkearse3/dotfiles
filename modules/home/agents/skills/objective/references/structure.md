# Structure

Objective registry layout, configuration, and file naming.

## Directory Structure

`.objectives/` is the objective registry. Entries are either real directories (default) or symlinks
to destination paths (configured). `_current` always points to the active entry.

### Default Mode (no `_config.yaml`)

Objective directories live directly in `.objectives/`. No symlink indirection.

```
.objectives/
  _current -> 2024-01-15-1430-auth-refactor   # symlink to active objective directory
  2024-01-15-1430-auth-refactor/               # real directory
    00-main.md
    01-phase-1.md
  2024-01-10-0930-fix-bug/
    00-main.md
```

### Configured Mode (with `_config.yaml`)

Objective entries are symlinks in `.objectives/` pointing to destination directories. Files live at
destination from the start.

```
.objectives/
  _current -> 2024-01-15-1430-auth-refactor   # symlink to active objective symlink
  _config.yaml                                 # destination config
  2024-01-15-1430-auth-refactor -> ../../docs/objectives/2024-01-15-1430-auth-refactor/
  2024-01-10-0930-fix-bug -> ../../docs/objectives/2024-01-10-0930-fix-bug/
```

Actual files at destination:

```
docs/objectives/2024-01-15-1430-auth-refactor/
  00-main.md                          # index: context, research, ACs, approach, phases index
  01-phase-1.md                       # phase 1 content (approach, tasks, issues)
  02-phase-2.md                       # phase 2 content
```

## Configuration

`.objectives/_config.yaml` — optional. When present, enables symlink mode with custom destinations:

```
destination_pattern: docs/objectives/<year>-<month>-<day>-<time>-<name>
```

Tokens (with shorthands):

- `<year>` / `<y>` - four-digit year
- `<month>` / `<m>` - two-digit month
- `<day>` / `<d>` - two-digit day
- `<time>` / `<t>` - four-digit time (`HHMM`, 24-hour)
- `<name>` / `<n>` - objective slug (without date/time prefix)

`/objective create` resolves destinations from this pattern. Without `_config.yaml`, objectives are
created as real directories in `.objectives/` with no prompt.

## Naming Conventions

- **Objective entry**: `<YYYY-MM-DD-HHMM>-<slug>` (date+time prefix for intra-day ordering)
- **Slugs**: lowercase, hyphens for spaces
- **Symlink targets** (configured mode): Always relative paths

## Sequence Counter

All files in the directory share one sequence counter. The next number is the highest existing `NN-`
prefix plus one; gaps are fine. `00-main.md` is always the root.

- Applies to all file types — phases, research, summaries, supplementary content.
- Keeps creation order visible in the directory listing.

## Supplementary Files

For overflow content (verbose research, benchmark data), create sequenced supplementary files:

```
03-research-api-analysis.md    # supplementary: detailed API research
04-research-benchmarks.md      # supplementary: benchmark data
```

Link from `00-main.md`:

```markdown
### Findings
- API supports batch mode — see [detailed analysis](./03-research-api-analysis.md)
```

Rules:

- `00-main.md` is always the primary index — supplementary files are linked from it
- Supplementary files are freeform (no required structure)
- Never put ACs, approach, or the phases index in supplementary files
- Phase files contain phase content and are registered from `00-main.md`
