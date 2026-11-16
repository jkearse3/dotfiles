// A core terminal as mods read it (`TerminalEntry`, with what runs in it now
// as `TerminalForeground`), and the addresses it carries: the machine part of
// an address (`machineOf`), a terminal's parent as a full address
// (`parentAddress`) and the longest walk up those parents (`MAX_ANCESTORS`).
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/terminals.ts` -> `../../mod-lib/terminals.ts`), and the
// herdr-app-mods build copies the file in place of the link and strips its
// types to `terminals.js`. The app refuses imports that leave a mod's own
// folder; `./terminals.js` beside the importing file is allowed.

import type { Program } from "herdr";

// The fields of a `terminals()` entry (a core terminal, agent or not) that
// the mods linking this file read. The app's typings type `terminals()`
// entries as `any`.
export interface TerminalEntry {
  // Bare on this computer, "<machine>/<id>" on another.
  address: string;
  // Its status as a plain word: an agent's `Status`, or another word such as
  // "error". Empty or missing for a terminal that reports none.
  status?: string | null;
  // The terminal that started it. A bare address refers to the machine of
  // the terminal that names it.
  parent?: string | null;
  // "live" while it runs.
  state?: string;
  // The name someone gave it.
  name?: string | null;
  program?: Program;
  // When its status last changed, in ms since the epoch.
  status_ms?: number | null;
  // Its agent's turn count from the core.
  turn?: number | null;
  // Its agent's status report (OSC 7501).
  report?: {
    app?: string;
    state?: string;
    msg?: string;
    // What a blocked agent waits for: "permission", "question" or "auth".
    // Null or missing when it is not blocked or did not say.
    kind?: string | null;
  };
  // Its core labels. `herdr.space` names the space it shows in, as an id
  // without the machine prefix. Null or missing when it has none.
  labels?: Record<string, string> | null;
  // The folder it started in on its machine; `foreground.cwd` is the one it
  // is in now.
  cwd?: string | null;
  // Its root process id: the process the core started in it.
  pid?: number | null;
  // What runs in it right now. Null or missing when the core reports none.
  foreground?: TerminalForeground | null;
}

// What runs in a terminal right now and where, from the core's terminal
// record: its foreground process, which is the terminal's root process
// (`TerminalEntry.pid`) while nothing else holds the terminal.
export interface TerminalForeground {
  // The foreground process's id.
  pid: number;
  // The process's name.
  name: string;
  // The command line it was started with, program first.
  argv: string[];
  // The folder it is in on the terminal's machine. Null or missing when the
  // core cannot tell.
  cwd?: string | null;
}

// The machine part of `address` ("<machine>/<id>"), or null for a terminal on
// this computer.
export function machineOf(address: string): string | null {
  const slash = address.indexOf("/");
  return slash > 0 ? address.slice(0, slash) : null;
}

// `child.parent` as a full address: a bare parent of a remote child lives on
// the child's machine. Null when it has no parent.
export function parentAddress(child: TerminalEntry): string | null {
  if (!child.parent) return null;
  if (child.parent.includes("/")) return child.parent;
  const machine = machineOf(child.address);
  return machine ? `${machine}/${child.parent}` : child.parent;
}

// The most steps a walk up `parent` links takes, so a parent cycle ends.
export const MAX_ANCESTORS = 32;
