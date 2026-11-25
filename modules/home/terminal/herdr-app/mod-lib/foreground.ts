// The command a plain terminal runs in its foreground (`runningCommand`),
// apart from its shell (`isShellProcess`, `shellCommandText`), as a row
// shows it (`commandText`), and when each started (`CommandStarts`), so a
// row shows a command only once it has run `COMMAND_SETTLE_MS` and quick
// commands do not make rows jump.
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/foreground.ts` -> `../../mod-lib/foreground.ts`), and the
// herdr-app-mods build copies the file in place of the link and strips its
// types to `foreground.js`. The app refuses imports that leave a mod's own
// folder; `./foreground.js` beside the importing file is allowed. It imports
// only types from `./terminals.js`, so linking `terminals.ts` beside it is
// enough.

import type { TerminalEntry, TerminalForeground } from "./terminals.js";

/**
 * The command running in `t`'s foreground: its process id and what a row
 * shows for it. A shell process (`isShellProcess`) runs a command only when
 * its command line names a script or a `-c` command (`shellCommandText`);
 * any other process is a command (`commandText`). Null when the core reports
 * no foreground, or one without a numeric pid, or when the foreground is an
 * interactive shell: the terminal's own, or one started inside it (`bash`,
 * `nix develop`).
 */
export function runningCommand(t: TerminalEntry): RunningCommand | null {
  const fg = t.foreground;
  if (!fg || typeof fg.pid !== "number") return null;

  const text = isShellProcess(t) ? shellCommandText(fg.argv) : commandText(fg);
  if (text === null) return null;
  return {
    pid: fg.pid,
    text,
  };
}

/** A command running in a terminal's foreground (`runningCommand`). */
export interface RunningCommand {
  /** The foreground process's id. */
  pid: number;
  /** What a row shows for it (`shellCommandText` or `commandText`). */
  text: string;
}

/**
 * Whether `t`'s foreground process is a shell program, interactive or
 * running a script. With a program, the app's program follows the
 * foreground process, so its `shell` flag decides. Without one, the
 * foreground is the shell when it is the terminal's root process
 * (`TerminalEntry.pid`). True when the core reports no foreground.
 */
export function isShellProcess(t: TerminalEntry): boolean {
  if (!t.foreground) return true;
  if (t.program) return t.program.shell;
  return t.foreground.pid === t.pid;
}

/**
 * What a shell started with `argv` runs, as a row shows it, or null when it
 * runs interactively. A shell runs a script when its first argument that is
 * not an option is a file: the row shows the script's file name without its
 * folder, then its arguments ("deploy.sh prod" for
 * `bash ./deploy.sh prod`, as a `#!/usr/bin/env bash` script starts). A
 * shell started with `-c` (alone or in a cluster such as `-lc`, or fish's
 * `--command`) runs the command string, which the row shows as it is
 * ("make dev" for `bash -c 'make dev'`). Options before it are skipped,
 * with the value of those that take one (`--rcfile <file>`, `-o <option>`),
 * so `bash --rcfile <file>` (as `nix develop` starts) and `bash -l` stay
 * interactive. An argument after `--` is a script.
 */
export function shellCommandText(argv: string[]): string | null {
  if (!Array.isArray(argv)) return null;
  let isCommandString = false;
  for (let i = 1; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--") {
      i++;
      if (i >= argv.length) return null;
      return isCommandString ? argv[i] : namedCommandText(argv.slice(i));
    }
    if (arg.startsWith("--command=")) return arg.slice("--command=".length);
    if (arg === "--command") isCommandString = true;
    else if (SHELL_OPTIONS_WITH_VALUE.has(arg)) i++;
    else if (/^-[^-]/.test(arg) && arg.includes("c")) isCommandString = true;
    else if (arg.startsWith("-") || arg.startsWith("+")) continue;
    else return isCommandString ? arg : namedCommandText(argv.slice(i));
  }
  return null;
}

/**
 * Shell options whose value is the next argument rather than a script:
 * bash's and zsh's, and fish's `-C`/`--init-command`.
 */
const SHELL_OPTIONS_WITH_VALUE = new Set([
  "--rcfile",
  "--init-file",
  "-o",
  "+o",
  "-O",
  "+O",
  "-C",
  "--init-command",
]);

/**
 * A command line (a program or script first) as a row shows it: the first
 * element's file name without its folder, then the rest, joined by single
 * spaces without quoting.
 */
function namedCommandText([file, ...args]: string[]): string {
  return [file.slice(file.lastIndexOf("/") + 1), ...args].join(" ");
}

/**
 * `fg`'s command line as a row shows it: the program's file name without
 * its folder, then the remaining arguments, joined by single spaces without
 * quoting ("make dev" for `/usr/bin/make dev`). The process name when the
 * core reports no arguments.
 */
export function commandText(fg: TerminalForeground): string {
  if (!Array.isArray(fg.argv) || fg.argv.length === 0) return fg.name;
  return namedCommandText(fg.argv);
}

/** How long a command runs before its row shows it, in ms. */
export const COMMAND_SETTLE_MS = 2000;

/**
 * How long `CommandStarts` keeps the start of a terminal gone from the
 * `terminals()` list, in ms: 30 days. The list alone is empty right after a
 * start, so a terminal missing from it may still be there.
 */
const GONE_KEEP_MS = 30 * 86400000;

/**
 * When the command in each plain terminal's foreground started, as the
 * sidebar first saw it (`track`), kept across restarts under the
 * `localStorage` key "commands", and the command a row shows once it has run
 * `COMMAND_SETTLE_MS` (`shown`).
 */
export class CommandStarts {
  declare starts: Record<string, CommandStart>;
  /** `shownKey` of the last `track` call's commands. */
  declare lastShown: string;

  constructor() {
    this.starts = readCommandStarts();
    this.lastShown = "";
  }

  /**
   * Stamps `now` on each live plain terminal of `entries` (one reporting no
   * status) whose running command is new or has a new process; keeps the
   * stamp of a command still running in the same process; drops the stamp
   * of one back at its shell or no longer a live plain terminal. Drops
   * terminals gone from `entries` for over 30 days. Saves only when a stamp
   * changed. Returns whether the commands rows show, or will show once
   * settled, changed since the last call: one started, ended, changed
   * process or crossed `COMMAND_SETTLE_MS`.
   */
  track(entries: TerminalEntry[], now: number): boolean {
    let dirty = false;
    const shown: string[] = [];
    for (const t of entries) {
      const cmd = t.state === "live" && !t.status ? runningCommand(t) : null;
      const last = this.starts[t.address];
      if (!cmd) {
        if (last) {
          delete this.starts[t.address];
          dirty = true;
        }
        continue;
      }

      if (last?.pid !== cmd.pid) {
        this.starts[t.address] = {
          pid: cmd.pid,
          at: now,
        };
        dirty = true;
      }
      const settled = now - this.starts[t.address].at >= COMMAND_SETTLE_MS;
      shown.push(`${t.address} ${cmd.pid} ${settled ? 1 : 0}`);
    }

    const listed = new Set(entries.map((t) => t.address));
    for (const [address, s] of Object.entries(this.starts))
      if (!listed.has(address) && now - s.at > GONE_KEEP_MS) {
        delete this.starts[address];
        dirty = true;
      }
    if (dirty) saveCommandStarts(this.starts);

    const key = shown.sort().join("\n");
    const changed = key !== this.lastShown;
    this.lastShown = key;
    return changed;
  }

  /**
   * The command `t`'s row shows: its running command's text and when it
   * started (ms since the epoch), once it has run `COMMAND_SETTLE_MS` by
   * `now`. Null when it runs none, `track` has not stamped this process, or
   * it has not run that long.
   */
  shown(t: TerminalEntry, now: number): ShownCommand | null {
    const cmd = runningCommand(t);
    const start = this.starts[t.address];
    if (!cmd || start?.pid !== cmd.pid) return null;
    if (now - start.at < COMMAND_SETTLE_MS) return null;
    return {
      text: cmd.text,
      since: start.at,
    };
  }
}

/** A command a row shows (`CommandStarts.shown`). */
export interface ShownCommand {
  /** What the row shows for it (`commandText`). */
  text: string;
  /** When it started, in ms since the epoch. */
  since: number;
}

/**
 * The foreground process of a terminal's running command and when it was
 * first seen, in ms since the epoch.
 */
interface CommandStart {
  pid: number;
  at: number;
}

/**
 * The stored starts, empty when storage has none or cannot be read, or holds
 * something else.
 */
function readCommandStarts(): Record<string, CommandStart> {
  let stored: unknown;
  try {
    stored = JSON.parse(localStorage.getItem("commands") ?? "{}");
  } catch {
    return {};
  }
  if (!stored || typeof stored !== "object") return {};

  const starts: Record<string, CommandStart> = {};
  for (const [address, s] of Object.entries(stored))
    if (s && typeof s.pid === "number" && typeof s.at === "number")
      starts[address] = {
        pid: s.pid,
        at: s.at,
      };
  return starts;
}

/**
 * Saves `starts`. A failed save only loses the starts across a restart,
 * after which the commands running then count from when they are next seen.
 */
function saveCommandStarts(starts: Record<string, CommandStart>): void {
  try {
    localStorage.setItem("commands", JSON.stringify(starts));
  } catch {}
}
