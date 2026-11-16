// Finished terminals (`FinishedTerminal`): terminals whose program ended but
// whose record the core keeps until someone removes it, as views list them
// under the live terminal that started them. It reads them from the CLI
// (`finishedAddresses` of `hc ls --all --json`, `finishedTerminalOf` of
// `hc get <address> --json`), checks the copy shared under
// `FINISHED_TERMINALS_KEY` (`readFinishedTerminals`), and says how one ended
// (`finishedOutcome`) and what its row is called (`finishedLabel`).
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/finished.ts` -> `../../mod-lib/finished.ts`), and the
// herdr-app-mods build copies the file in place of the link and strips its
// types to `finished.js`. The app refuses imports that leave a mod's own
// folder; the `./space-order.js` and `./terminals.js` this file imports must
// be linked beside it too. It imports nothing from `herdr`, so
// `mod-lib-test.mjs` can test it under Node.

import { base } from "./space-order.js";
import { parentAddress } from "./terminals.js";

// A finished terminal: one whose core record says `state` "finished".
export interface FinishedTerminal {
  // Bare on this computer, "<machine>/<id>" on another.
  address: string;
  // The full address of the terminal that started it (a bare parent of a
  // remote terminal qualified with its machine, as `parentAddress` does);
  // null when nothing did.
  parent: string | null;
  // The name someone gave it; null when unnamed.
  name: string | null;
  // The file name of the program it ran (`argv[0]` without its folder):
  // "make" for `/usr/bin/make`; null when the core recorded no argv.
  command: string | null;
  // Its folder on its machine.
  cwd: string;
  // Its program's exit code; null when it gave none (killed, signalled or
  // lost).
  exitCode: number | null;
  // The signal that ended its program; null when none did.
  signal: number | null;
  // The core's word for why its program ended: exited, killed, signaled,
  // holder_lost, stopped_by_restart, server_stop or host_shutdown; null when
  // the core gave none.
  reason: string | null;
  // When it finished, in ms since the epoch; 0 when the core did not say.
  finishedMs: number;
}

// The `shared()` key of the finished terminals the desk-spaces sidebar
// reads from the CLI, as an array of `FinishedTerminal`, for views that run
// no `hc` of their own; `readFinishedTerminals` checks what it holds. The
// sidebar writes it (`publishFinished` in `mods/desk-spaces/main.ts`) with
// only the finished terminals whose parent is live, the ones a tree nests,
// whenever that set changes. The find hub drops one it removed with `hc rm`
// (`unshareFinished` in `mods/find/main.ts`), and the sidebar, seeing a value
// it did not write, reads the CLI again (`followFinished`). The value
// persists, so while no sidebar runs it holds what the last one wrote.
export const FINISHED_TERMINALS_KEY = "terminals.finished";

// `value`, as `shared(FINISHED_TERMINALS_KEY)` returns it, as finished
// terminals with only `FinishedTerminal`'s fields, in its order. Empty when
// `value` is not an array; an entry that is not a finished terminal is left
// out.
export function readFinishedTerminals(value: unknown): FinishedTerminal[] {
  if (!Array.isArray(value)) return [];

  const isNumberOrNull = (v: unknown) => v === null || typeof v === "number";
  const isStringOrNull = (v: unknown) => v === null || typeof v === "string";
  return value.flatMap((f): FinishedTerminal[] =>
    f &&
    typeof f === "object" &&
    typeof f.address === "string" &&
    isStringOrNull(f.parent) &&
    isStringOrNull(f.name) &&
    isStringOrNull(f.command) &&
    typeof f.cwd === "string" &&
    isNumberOrNull(f.exitCode) &&
    isNumberOrNull(f.signal) &&
    isStringOrNull(f.reason) &&
    typeof f.finishedMs === "number"
      ? [
          {
            address: f.address,
            parent: f.parent,
            name: f.name,
            command: f.command,
            cwd: f.cwd,
            exitCode: f.exitCode,
            signal: f.signal,
            reason: f.reason,
            finishedMs: f.finishedMs,
          },
        ]
      : [],
  );
}

// The addresses of the finished terminals in `stdout`, the output of
// `hc ls --all --json` (`{"terminals": [{"address", "state", …}, …]}`), in
// its order. Null when `stdout` is not that output, so a caller can tell a
// failed read from no finished terminals.
export function finishedAddresses(stdout: string): string[] | null {
  const listing = parseJson(stdout);
  if (!listing || !Array.isArray(listing.terminals)) return null;

  return listing.terminals.flatMap((t: unknown) => {
    const entry = t as { address?: unknown; state?: unknown } | null;
    return entry &&
      typeof entry.address === "string" &&
      entry.state === "finished"
      ? [entry.address]
      : [];
  });
}

// The finished terminal at `address` (the address it was asked for, as
// `hc ls` gave it) from `stdout`, the output of `hc get <address> --json`
// (a core `Terminal`). Null when `stdout` is not a terminal's JSON or the
// terminal is not finished.
export function finishedTerminalOf(
  address: string,
  stdout: string,
): FinishedTerminal | null {
  const t = parseJson(stdout);
  if (!t || t.state !== "finished") return null;

  const argv0 = Array.isArray(t.argv) ? t.argv[0] : undefined;
  const command = typeof argv0 === "string" ? base(argv0) || null : null;
  const parent = typeof t.parent === "string" ? t.parent : null;
  return {
    address,
    parent: parentAddress({
      address,
      parent,
    }),
    name: typeof t.name === "string" && t.name !== "" ? t.name : null,
    command,
    cwd: typeof t.cwd === "string" ? t.cwd : "",
    exitCode: typeof t.exit_code === "number" ? t.exit_code : null,
    signal: typeof t.signal === "number" ? t.signal : null,
    reason: typeof t.reason === "string" ? t.reason : null,
    finishedMs: typeof t.finished_ms === "number" ? t.finished_ms : 0,
  };
}

// How a finished terminal's program ended, as its row shows it: `failed`
// unless it exited 0, and `text` saying how: "killed" when someone killed
// it, "lost" when nothing was left to run it (its holder died, a restart,
// the server stopping or the computer shutting down), "signal N" when a
// signal ended it, "exit N" for its exit code, else the core's reason, or
// "ended" without one.
export function finishedOutcome(f: FinishedTerminal): {
  failed: boolean;
  text: string;
} {
  if (f.reason === "killed")
    return {
      failed: true,
      text: "killed",
    };
  if (f.reason !== null && LOST_REASONS.has(f.reason))
    return {
      failed: true,
      text: "lost",
    };
  if (f.signal !== null)
    return {
      failed: true,
      text: `signal ${f.signal}`,
    };
  if (f.exitCode !== null)
    return {
      failed: f.exitCode !== 0,
      text: `exit ${f.exitCode}`,
    };
  return {
    failed: true,
    text: f.reason ?? "ended",
  };
}

// The core reasons that mean a program ended because nothing was left to
// run it, not by its own exit or a kill.
const LOST_REASONS = new Set([
  "holder_lost",
  "stopped_by_restart",
  "server_stop",
  "host_shutdown",
]);

// What a finished terminal's row is called: its name, else its command,
// else its address.
export function finishedLabel(f: FinishedTerminal): string {
  return f.name ?? f.command ?? f.address;
}

// `text` parsed as a JSON object; null when it is not one.
function parseJson(text: string): Record<string, unknown> | null {
  try {
    const value: unknown = JSON.parse(text);
    return value && typeof value === "object" && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}
