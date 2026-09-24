# Pi extensions

This directory is the source for Pi's standard global extension path:

```text
~/.pi/agent/extensions
```

In editable Home Manager mode that path is a symlink into this checkout. Pi
auto-discovers `*/index.ts`, and `/reload` applies source changes without a Home
Manager rebuild.

## Transcript stamps

The `transcript-stamps` extension adds dim, right-aligned rows with a one-column
right margin after user messages and at the close of assistant turns (after any
tool rows). Its fixed defaults are local 24-hour time with seconds and an
explicit UTC offset, a date on the first stamp and at local day changes,
first-content latency, assistant response and complete-turn duration, aggregate
tool wall time/count/errors, and reported output-token throughput. A separate
`agent … · N turns` row appears when Pi settles, measuring the full wall-clock
busy period from the first agent start through retries, continuations, steers,
and any queued follow-ups before settling. Aborted responses mark it
interrupted; it is not a per-prompt attribution. Timing values are local Pi
observations rather than provider telemetry.

Stamp entries persist in the session but remain outside model context. The
extension performs no settings or network I/O, starts no timers or background
work, and caches rendered output by terminal width.

## Create an extension

Use a directory with an `index.ts` entry point and keep helpers and fixtures
beside it:

```text
extensions/
└── example/
    ├── index.ts
    ├── helper.ts
    └── helper.test.ts
```

All extension sources must be TypeScript. The repository checks imports, runs
`tsc`, and executes every `*.test.ts` fixture.

## Subscription usage

The `usage` extension is the locally owned, dependency-free home for
subscription quota and billing views. `/usage` checks every supported provider
with configured Pi authentication. Only an explicit command can start provider
work; the extension performs no background polling. Codex is the first adapter.

Adapters own provider detection, official-origin authentication checks,
transport, normalization, provider-specific semantics, and non-secret credential
fingerprints. A shared coordinator keeps successful reports in a bounded
process-local cache for five minutes and deduplicates matching in-flight
requests. The dashboard identifies provider versus cached data and shows its
age. Press `r` in the results view to bypass a fresh cache entry. The registry
preserves adapter order, bounds concurrency, and keeps partial failures visible.
Shared transport refuses redirects, bounds response bodies, redacts credentials
from errors, and never forwards provider headers other than the required
authorization.

The provider-adapter approach was initially inspired by the MIT-licensed
[`pi-usage` extension](https://github.com/narumiruna/pi-extensions/tree/main/packages/pi-usage).
This local implementation is independently maintained and expected to diverge as
its provider coverage and safety model evolve.

## Edit the last prompt

The `edit-last-prompt` extension treats two Escape presses within 500 ms as an
“edit and retry” gesture when the first press interrupted an active run. It
aborts the run, rewinds the active session branch to before its latest user
message, and restores that message in the editor. Files changed before the
interrupt remain changed. The same behavior is available explicitly through
`/edit-last-prompt`.

Idle double-Escape behavior remains owned by Pi's `doubleEscapeAction` setting,
and a non-empty draft is never overwritten.

## Herdr lifecycle integration

`herdr-agent-state.ts` is intentionally a relative symlink to the official Pi
integration in the active Nix profile. This gives Herdr its canonical installed
filename, so `herdr integration status` verifies the same artifact shipped by
the installed Herdr package instead of a copied extension.

Editable delivery preserves that profile-relative link. Locked delivery replaces
it with a direct link to the selected `dotfilesPackages.herdr` artifact, and the
Home Manager build checks the integration identity, version marker, and source
link target. Do not run `herdr integration install pi`; Home Manager owns the
canonical path.

## Add a runtime dependency

All global extensions share this directory's npm dependency set. From any
working directory, install through Pi's canonical path:

```bash
npm install --prefix ~/.pi/agent/extensions <package>
```

npm saves an exact version, updates `package-lock.json`, and writes the
Git-ignored `node_modules`. Install scripts are disabled by `.npmrc`; review a
package before making any exception for generated or native artifacts.

After switching revisions or on a fresh editable checkout, restore exactly the
locked dependency tree:

```bash
npm ci --prefix ~/.pi/agent/extensions
```

Only packages in `dependencies` are importable by extension source. Nix rebuilds
the same lockfile independently for checks and locked Home Manager delivery, so
local `node_modules` is never trusted as release input.
