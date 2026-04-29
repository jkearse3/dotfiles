# Structure

## Directory Structure

`.claude/_goals/` is the goal registry. Entries are either real directories (default) or symlinks
pointing to destination paths (configured). `_current` always points to the active entry.

### Default Mode (no `_config.yaml`)

Goal directories live directly in `.claude/_goals/`. No symlink indirection.

```
.claude/_goals/
  _current -> 2024-01-15-1430-auth-refactor   # symlink to active goal directory
  2024-01-15-1430-auth-refactor/               # real directory
    00-main.md
    01-phase-1.md
  2024-01-10-fix-bug/                          # old format coexists
    00-main.md
```

### Configured Mode (with `_config.yaml`)

Goal entries are symlinks in `.claude/_goals/` pointing to destination directories. Files live at
destination from the start.

```
.claude/_goals/
  _current -> 2024-01-15-1430-auth-refactor   # symlink to active goal symlink
  _config.yaml                                 # destination config
  2024-01-15-1430-auth-refactor -> ../../docs/goals/2024-01-15-1430-auth-refactor/
  2024-01-10-fix-bug -> ../../docs/goals/2024-01-10-fix-bug/
```

Actual files at destination:

```
docs/goals/2024-01-15-1430-auth-refactor/
  00-main.md                          # index: context, research, ACs, approach, phases index
  01-phase-1.md                       # phase 1 content (approach, tasks, issues)
  02-phase-2.md                       # phase 2 content
```

## Configuration

`.claude/_goals/_config.yaml` — optional. When present, enables symlink mode with custom
destinations:

```
destination_pattern: docs/goals/<year>-<month>-<day>-<time>-<name>
```

Tokens (with shorthands):

- `<year>` / `<y>` - four-digit year
- `<month>` / `<m>` - two-digit month
- `<day>` / `<d>` - two-digit day
- `<time>` / `<t>` - four-digit time (`HHMM`, 24-hour)
- `<name>` / `<n>` - goal slug (without date/time prefix)

`/goal create` resolves destinations from this pattern. Without `_config.yaml`, goals are created as
real directories in `.claude/_goals/` with no prompt.

## Naming Conventions

- **Goal entry**: `<YYYY-MM-DD-HHMM>-<slug>` (date+time prefix for intra-day ordering)
- **Old format**: `<YYYY-MM-DD>-<slug>` (coexists with new format, no migration)
- **Slugs**: lowercase, hyphens for spaces
- **Symlink targets** (configured mode): Always relative paths

## Sequence Counter

All files in the directory share a single sequence counter. Next number = highest existing `NN-`
prefix in the directory + 1. Gaps are fine. `00-main.md` is always the root.

The counter applies to all file types — phases, research, summaries, or any other supplementary
content. This keeps creation order visible in the directory listing.

## Supplementary Files

For overflow content (verbose research, benchmark data, etc.), create sequenced supplementary files:

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
- Phase files follow the phase template (see Templates)
