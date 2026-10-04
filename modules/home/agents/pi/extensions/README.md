# Pi extensions

This directory is the source for Pi's standard global extension path:

```text
~/.pi/agent/extensions
```

In editable Home Manager mode that path is a symlink into this checkout. Pi
auto-discovers `*/index.ts`, and `/reload` applies source changes without a Home
Manager rebuild.

## Subagents

The `subagent` tool is the sole Pi delegation mechanism. Each call runs a
short-lived Pi process in the foreground, streams live activity, waits for
completion, and returns the final assistant response with model usage. Omit
`conversationId` to create a durable conversation; pass a returned ID to spawn a
new process that continues the same child message and tool history. The durable
conversation is state, not a persistent agent or process. Interrupting a call
stops its owned process group without rolling back source changes and preserves
the last valid conversation checkpoint.

Resume the same line of inquiry when prior findings, rejected hypotheses, or
loaded files remain useful. Start fresh for independent, parallel, or unbiased
work, materially changed scope, or stale/large context. Resumption avoids
repeated discovery but sends the retained history again and continues consuming
the model context window. For independent fan-out, issue multiple fresh subagent
calls in the same turn; one conversation cannot execute concurrently and there
is no background job API.

```json
{"label":"implement","prompt":"You own src/example.ts only. Implement the requested change, run applicable tests, and report the diff and limitations. Do not finalize or publish."}
{"label":"find-auth","prompt":"Find authentication entry points. Report file paths, evidence, and limitations.","tools":["read","grep","find","ls"],"extensions":false,"skills":[]}
{"label":"adversarial-review","prompt":"Use diff-review to review revision <revision>.","tools":["read","grep","find","ls","bash"],"extensions":false,"skills":["diff-review"]}
```

Conversation metadata is stored as branch-sensitive custom entries in the
persisted parent Pi session and is excluded from model context. Full child Pi
sessions live under a private `$XDG_STATE_HOME/pi/subagent-conversations`
namespace. They survive extension reloads, switching away and back, and Pi
restarts. `subagent_conversations` returns a bounded catalog for the active
parent-session branch when an old ID is no longer visible; it never returns
child transcripts or storage paths. Parents started with `--no-session` still
run fresh ephemeral children but cannot create or resume durable conversations.

Children use normal configured Pi capabilities by default, including shell,
edit, write, extensions/MCP, and skills. Per-task capability controls are:

- `tools`: optional active tool allowlist. Omit for configured defaults; `[]`
  disables all tools. Built-in and configured extension tool names are accepted.
  This selects active tools, not an OS permission boundary or a guarantee about
  what extension code or tools calling other tools can do.
- `extensions`: defaults to `true`. Set `false` to disable configured extensions
  and MCP. A minimal coordinator guard is still explicitly loaded, but never
  exposes delegation to children. Disable extensions as well as narrowing tools
  for read-only tasks; extensions can execute code independently of tool calls.
- `skills`: optional managed skill-name allowlist. Omit it for normal discovered
  skills, pass `[]` for no skills, or name only the skills the child may use.
  Unknown, duplicate, and malformed names fail before spawn. Explicit names
  resolve under the managed user skill directory; project or package-specific
  skills require normal discovery. A durable conversation keeps its original
  skill selection; start fresh to change it so prior skill context cannot bypass
  a narrower continuation. Conversations created by extension versions without
  stored skill policies must be restarted fresh.

The tool returns the requested capability settings for inspection. An omitted
`tools` field means configured defaults, not a frozen copy of the parent's live
tool selection. Tools enabled only through the parent's explicit CLI extensions
or runtime changes are not automatically copied. Prompt templates and themes are
unnecessary for headless tasks and remain disabled.

The default model and thinking level match the caller. An explicit `model`
overrides only the model; thinking remains the caller's selected level, clamped
by Pi to the child's capabilities. Children receive context files, including
repository instructions, but never the parent's conversation, runtime prompt
changes, or extension state. A continuation receives only its own persisted
child conversation. Project resources inherit the parent's trust only when the
child's canonical cwd exactly matches the caller's; a different cwd is never
automatically approved. Child processes cannot show interactive approval
dialogs; they must report blockers. The `subagent` tool is excluded from child
loadouts and guarded against nested calls. The `PI_SUBAGENT=1` marker identifies
delegated processes cooperatively; it is not an authentication boundary.

Capabilities are not authority. Write assignments must explicitly name
nonoverlapping ownership and verification, preserve unrelated work, and leave
review and repository finalization to the coordinator. Cancellation and shutdown
do not undo source changes. Tool selection is not an OS sandbox: children
inherit the process's credentials and OS permissions, including an existing
sandbox. Parent Herdr and shell-session identity markers are removed from their
environment.

The TUI uses compact tool receipts instead of raw JSON. Ctrl+O expands the
assignment, a chronological visible transcript, final Markdown outcome, task
metadata, requested capabilities, and private artifact paths. The transcript
includes assistant commentary, tool targets and statuses, and bounded output
previews for shell and discovery tools. It excludes hidden reasoning, read
contents, write/edit payloads, and arbitrary unknown-tool output. Running
foreground blocks show elapsed time and up to four recent tool calls, refreshed
on events and once a second. Each call updates in place from running to
completed, failed, or cancelled. Completed receipts summarize input, output,
cache-read, and cache-write tokens, the latest response's cache-hit rate, and
estimated cost. Expanded results include exact token and cost breakdowns,
overall and latest cache-hit rates, provider-reported reasoning and one-hour
cache-write subsets, and whether compaction usage is included. These diagnostics
cover the current foreground execution; Pi also attributes their native tool
usage to the parent session's cumulative totals. Provider pricing or
subscription semantics may make monetary cost zero or approximate. Usage
rendering is excluded from tool content and structured output, like the visible
transcript, so it does not enlarge coordinator model context. Previews show
relative file paths, read ranges, search patterns and directories, or commands.
Compact task metadata retains the eight most recent calls; expanded current
results render up to 64 chronological transcript entries. Unknown tools show
argument names only, not their values. Common credential patterns are redacted
before previews are bounded to 600 characters; this is best-effort, not a
guarantee that arbitrary commands contain no sensitive text. Reports include
bounded `toolCalls` previews and result limits. The renderer receives up to 64
UI-only transcript entries (4,000 characters per assistant entry and six
lines/1,200 characters per eligible tool output); it reports omitted older
entries. The transcript is excluded from tool content and structured output, so
it does not enlarge the coordinator model's context. Older session entries
without transcripts still render their activity summaries.

Each child stays inside its tool block. Deeper monitoring is available through
the task's private `events.jsonl` and `stderr.log` for the session lifetime.
These logs may contain prompts, file contents, model thinking, or secrets. Tool
previews omit file payloads and thinking but may expose paths, search terms, and
commands. `reply.txt` contains the full final response; tool results are capped
at 16,000 characters and identify truncation. Completion requires process exit,
`agent_settled`, and a nonempty successful final assistant response. Partial
text and JSON-mode exit status alone are not treated as success.

At most four children run concurrently and 32 tasks may be created per parent
runtime; there is no queue or runner-level retry. A branch catalog retains the
32 most recently used conversations. Continuations reject child sessions larger
than 64 MiB; unlocked storage becomes eligible for deletion after 30 days
without use and uses exclusive cross-process locks. Unknown IDs, another parent
branch, a changed canonical cwd, malformed state, and live or unverifiable locks
fail closed rather than creating a blank conversation. Current model, thinking,
capabilities, and project trust are reapplied on every continuation; persisted
history is context, not authority. Pi's own provider retries still apply.

Combined invocation logs are capped at 32 MiB per task and a single event at 8
MiB; exceeding either fails and stops the task. Temporary task artifacts remain
available until parent-session cleanup. Reloading, replacing the parent session,
or shutting down stops remaining children and deletes those temporary
directories while retaining durable conversations. A hard parent crash can leave
a child or temporary artifacts behind. A later continuation refuses a still-live
child and only recovers a confirmed lock when both recorded processes are
definitely gone. A malformed or spawn-unconfirmed crash lock remains fail-closed
rather than risking concurrent writers and may retain storage beyond normal
expiry; source changes are never rolled back.

In editable mode, `/reload` discovers this extension without a rebuild. The
updated delegation instructions require Home Manager activation to reach the
generated global `AGENTS.md`. The legacy `pi-shepherd` package, skill, launch
configuration, and sandbox grants have been removed from managed configuration.
Existing legacy runtime databases and unrelated live teammates are not migrated
or deleted.

## Transcript stamps

The `transcript-stamps` extension shows a dim, left-aligned local time after
each user message and a single elapsed-time summary when the agent settles. Both
rows keep a one-column right margin. Newly recorded stamps show the date and UTC
offset on the first visible stamp and on local day changes; routine rows show
only the time. The summary includes the settled clock time, agent wall time,
turn count, and an interruption marker when applicable. Steers and queued
follow-ups before settlement are part of the same busy period, not attributed to
one prompt.

```text
2026-01-02 · 14:00:01 UTC-05:00
14:02:15 · agent 2m 14s · 5 turns
```

Assistant turn timing sidecars remain persisted but hidden by default, including
in older sessions. `/timings` toggles their original transcript rows on or off
for the current Pi process. These rows show first-content latency, response and
turn time, tool activity, and token throughput when observed. The command does
not add a report or change model context. Pi may not repaint off-screen terminal
scrollback immediately; newly rendered transcript rows follow the current
toggle.

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

All extension sources must be TypeScript. `./x.sh pi-extensions-check`
typechecks the working tree and runs its `*.test.ts` fixtures by building the
`pi-extensions-checked` package; the Home Manager build depends on the same
package, so a failing check also fails the switch.

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

## Types for Pi's modules

Pi supplies its own modules to extensions at load, so they are not npm
dependencies of this directory. Their declarations come from the
`pi-extension-types` package, built from the Pi that Home Manager installs, and
reach this directory as the Git-ignored `.pi-types` link:

```text
.pi-types/
├── node_modules/     declarations for Pi and its dependency tree
└── tsconfig.json     maps each importable Pi module to its declaration
```

`tsconfig.json` here extends `.pi-types/tsconfig.json`, so the modules an
extension may import from Pi are listed once, in
`packages/pi-extension-types/package.nix`. Change that list when a Pi release
adds, renames, or removes a module; the package build fails if a listed
declaration is missing. Do not add `paths` or `baseUrl` to `tsconfig.json` here,
because either replaces the inherited mappings.

The devshell creates the link on entry and refreshes it after a Pi version bump.
Only editors read it: the `pi-extensions-checked` package links the same
declarations into its own copy of the sources.

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

Import only packages listed in `dependencies`. Nix rebuilds the same lockfile
independently for the typecheck and for locked Home Manager delivery, so local
`node_modules` is never trusted as release input, and an import that typechecks
is one the delivered tree can load. The typecheck does not stop an import of a
package that is installed only because another dependency pulls it in.
