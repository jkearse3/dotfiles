# Architecture

The CLI is short-lived. Durable intent belongs to SQLite; runtime health belongs
to a fresh validated Herdr snapshot; the sole reply body belongs to an exact
request slot. There is no daemon, transcript reader, session adapter, queue,
notification path, or result history.

## Search map

| Concern                                                    | Module under `src/pi_shepherd` |
| ---------------------------------------------------------- | ------------------------------ |
| Grammar, dispatch, JSON/human output, flush-before-ack     | `cli.py`                       |
| Pi profiles and bounded caller twinning                    | `config.py`                    |
| IDs, immutable names, exact markers, cwd                   | `ids.py`                       |
| Durable record types and ephemeral topology                | `models.py`                    |
| Stable sanitized failures and required-value checks        | `errors.py`                    |
| Private paths, links/modes, bounded advisory locks         | `private_fs.py`, `locks.py`    |
| Two-table schema, revision CAS, atomic request transitions | `registry.py`                  |
| Protocol-22 decoder and one-invocation subprocess boundary | `herdr.py`                     |
| Caller terminal and canonical endpoint resolution          | `context.py`                   |
| Pure health and repair proposals                           | `topology.py`                  |
| Lifecycle effects, fresh fences, apply-time repair checks  | `teammates.py`                 |
| Cooperative dispatch, exact reply, retrieval and waits     | `messages.py`                  |
| Unverified read, lifecycle wait, focus, interactive attach | `terminal.py`                  |

`topology.derive` performs no I/O. It requires a validated complete snapshot,
scans the entire endpoint for identity conflicts, and never selects by
similarity. `Team.observe` applies only proof-preserving transitions under
bounded revision checks, then takes another snapshot; callers cannot reuse
pre-transition evidence to authorize an effect. Name resolution rechecks the
current workspace under its lock and rejects changed name bindings. Tab labels
combine the immutable task name with the complete identity marker. Marker
detection searches for the complete identity marker, then accepts only the exact
current `NAME [pi-shepherd:TEAMMATE_ID]` label so stale or conflicting labels
cannot conceal duplicate identities.

The concrete Herdr boundary validates required fields, full parent/count/focus
consistency, and operation response identity. Native-session and unrelated API
fields are ignored rather than retained. Missing observations never prove
absence. Canonical endpoint identity comes from the explicit local socket path;
current routing is resolved from `pane.current` terminal identity against a
fresh snapshot.

## Intent and effects

The two tables are `teammates` and `requests`. Active names have a unique
partial endpoint/workspace/name index. Requests have a unique teammate foreign
key and one random request ID. The row is either pending or
completed-unacknowledged; ack/cancel deletes it. Public request output keeps
that durable state separate from wait outcomes and fresh runtime diagnostics.
There are no observation columns or historical result rows.

Create records provisioning intent before startup. This phase can mean an
in-flight start, so alias absence alone never authorizes another start. The
exact alias can prove promotion; otherwise a known safe tab can be closed and
replaced through explicit commands. Missing managed agents likewise require
explicit close/create, never in-place restart: the API cannot reapply and verify
current profile environment in an existing shell. Close requires
foreground-shell proof for agent-free panes. Closing records intent before the
exact tab-close invocation and finalizes only after tab, marker, and alias are
absent.

Topology-changing operations acquire the endpoint lock before the teammate lock.
This prevents two cooperating closes from both passing final-tab counting.
Request/terminal operations use the teammate lock. SQLite unique constraints and
conditional updates remain the final fence for non-locking request cancellation
and acknowledgement. Locks are released before polling replies; reply itself
revalidates the managed caller while holding the teammate lock.

External effects are not SQLite transactions. There is one invocation per
effect, with no retry decorator. Unknown mutation failures, malformed success,
and wrong-binding responses are uncertain. A committed `prepared` request
remains nonreplayable even if a process dies before the external invocation. A
delivery update touches only that request's delivery field and cannot replace an
early reply. Result output failure happens before acknowledgement, preserving
the slot.

These locks coordinate this CLI, not humans or raw Herdr. The server has no
expected-binding mutation precondition; post-preflight external races remain a
runtime limitation, not a guarantee hidden behind local revision numbers.

## Validation boundaries

- Foundation tests cover grammar, removed options, exact Pi profiles, and caller
  twinning.
- Registry/concurrency tests exercise real disposable SQLite connections and
  advisory locks, name scoping, CAS, one-slot races, stale replies and private
  paths.
- Pure topology tests cover ambiguity, contamination, absence, and proposals.
- Lifecycle/inbox tests use a domain fake; they check effect ordering, crash
  intent, uncertainty, reply attribution, explicit repair and flush-before-ack.
- Herdr wire tests independently cover schema shapes, malformed topology,
  current terminal resolution, response identity, process proof, and sanitized
  failures.
- Nix installation checks run outside the source tree, verify store imports and
  exact skill bytes, and execute nonmutating JSON discovery with disposable
  config.
- Live protocol compatibility and the cooperative exchange require a separately
  authorized disposable smoke test; fake-domain tests do not prove external
  behavior.

Keep production Python at or below 5,000 lines, Python tests/support at or below
6,500, and the tracked package at or below 13,000. Measure physical lines and
module/command/schema counts. Do not grow repair into candidate ranking,
retries, queues, result history, provider parsing, or another orchestration
framework.
