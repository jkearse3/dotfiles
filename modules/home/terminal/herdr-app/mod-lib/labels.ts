// How a view names a live terminal: what its row shows, all in one
// (`terminalRowModel`), and the parts: the program it runs (`programOf`), an
// agent's label (`agentLabel`), a plain terminal's label (`plainLabel`), the
// folder a row shows for it (`folderOf`, `homeRelative`), and what an agent
// row's third line says it is doing (`agentDoing`, `blockedKind`). A plain
// terminal's third line, when it has one, is the command it runs, which the
// caller works out (`foreground.ts`) and passes in. A label
// starts with the program's short name, as a process list would show it,
// followed by the terminal's title, what names it beyond its program
// ("claude  Fix the sidebar"), or by its folder when it has no name
// ("fish  ~/x"). A row draws the short name and the title apart, with the
// folder on a line of its own.
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/labels.ts` -> `../../mod-lib/labels.ts`), and the
// herdr-app-mods build copies the file in place of the link and strips its
// types to `labels.js`. The app refuses imports that leave a mod's own
// folder; the `./names.js`, `./terminals.js` and `./tree.js` this file
// imports must be linked beside it too (`./status.js` gives only a type). It imports only types from `herdr`,
// so `mod-lib-test.mjs` can test it under Node.

import type { Program } from "herdr";
import { agentActivity, agentName } from "./names.js";
import type { AgentStatus } from "./status.js";
import { machineOf } from "./terminals.js";
import type { TerminalEntry } from "./terminals.js";
import type { TreeTerminal } from "./tree.js";

/**
 * What the row of tree terminal `node` shows (`TerminalRowModel`), with
 * this computer's `home` written as `~` in its folders. Every terminal
 * shows the folder it is in now. A terminal reporting a status is an agent:
 * its `agentLabel`, its status and what it is doing (`agentDoing`); it
 * ignores `command`. Any other terminal is plain: its `plainLabel`, with
 * `command` as its detail (a "command" `TerminalRowDetail`), the command
 * running in its foreground that its row shows; no detail when `command` is
 * null or absent.
 */
export function terminalRowModel(
  node: Pick<TreeTerminal, "terminal" | "info" | "pane" | "status">,
  home: string,
  command?: Pick<CommandDetail, "text" | "since"> | null,
): TerminalRowModel {
  const t = node.terminal;
  const program = programOf(node);
  const programName = shortProgramName(program);
  if (node.status === null) {
    return {
      address: t.address,
      label: plainLabel(node, home),
      program,
      programName,
      title: plainTitle(node),
      status: null,
      folder: folderOf(t, home),
      detail: command
        ? {
            kind: "command",
            text: command.text,
            since: command.since,
          }
        : null,
    };
  }

  const activity = node.info
    ? agentActivity(node.info, {
        name: t.name ?? undefined,
        report: t.report,
      })
    : null;
  return {
    address: t.address,
    label: agentLabel(node),
    program,
    programName,
    title: agentTitle(node),
    status: node.status,
    folder: folderOf(t, home),
    detail: agentDoing({
      status: node.status,
      reportKind: t.report?.kind || null,
      activity,
    }),
  };
}

/**
 * What a terminal's row shows (`terminalRowModel`); `tree-rows.ts`
 * `terminalRow` draws it.
 */
export interface TerminalRowModel {
  address: string;
  /** An agent's `agentLabel`, a plain terminal's `plainLabel`. */
  label: string;
  /** `programOf` the terminal; null when none names one. */
  program: Program | null;
  /**
   * What the label calls `program`, as a process list would ("claude",
   * "fish"); null without a program or a name for it.
   */
  programName: string | null;
  /**
   * What names the terminal beyond its program, which its row draws after
   * `programName`: an agent's `agentTitle`, a plain terminal's
   * `plainTitle`. Null when its name only repeats the program's, and for an
   * unnamed plain terminal with a `programName`.
   */
  title: string | null;
  /**
   * An agent's own status (`TreeTerminal.status`); null for a plain
   * terminal, whose row shows no status.
   */
  status: AgentStatus | null;
  /**
   * The folder the terminal is in now, as `folderOf` writes it; null when
   * it reports no folder.
   */
  folder: string | null;
  /**
   * What the row's third line says: what an agent is doing (`agentDoing`),
   * or the command a plain terminal runs; null for a plain terminal running
   * none, whose row has no third line.
   */
  detail: TerminalRowDetail | null;
}

/**
 * What a row's third line says, and which kind of thing that is, which sets
 * how the row draws it: for an agent, what it is doing (`AgentDetail`); for
 * a plain terminal, the command it runs (`CommandDetail`).
 */
export type TerminalRowDetail = AgentDetail | CommandDetail;

/**
 * What an agent row's third line says (`agentDoing`), by kind:
 * - "blocked": what a blocked agent waits for (`blockedKind`), such as
 *   "permission";
 * - "activity": what the agent says it is doing now ("Reading the docs");
 * - "status": the agent's status word ("working", "idle", "done"), when it
 *   says neither.
 */
export interface AgentDetail {
  kind: "blocked" | "activity" | "status";
  text: string;
}

/**
 * The command running in a plain terminal's foreground, as its row's third
 * line shows it.
 */
export interface CommandDetail {
  kind: "command";
  /** The command line ("make dev"). */
  text: string;
  /**
   * When it started, in ms since the epoch; null when the view does not
   * know, and the row then shows no run time.
   */
  since: number | null;
}

/**
 * The program `node` runs: its `terminals()` entry's, else its `agents()`
 * entry's, else its pane's; null when none names one.
 */
export function programOf(
  node: Pick<TreeTerminal, "terminal" | "info" | "pane">,
): Program | null {
  return (
    node.terminal.program ?? node.info?.program ?? node.pane?.program ?? null
  );
}

/**
 * An agent's label: `programOf(node)`'s short name and its `agentTitle`,
 * two spaces apart ("claude  Fix the sidebar"); the short name alone when
 * it has no title.
 */
export function agentLabel(
  node: Pick<TreeTerminal, "terminal" | "info" | "pane">,
): string {
  return labelOf(shortProgramName(programOf(node)), agentTitle(node));
}

/**
 * An agent's title: `agentName` of its `agents()` entry; without one, the
 * terminal's name, else its program's full name, else its address. Null
 * when that only names the program (`titleAfterProgram`).
 */
function agentTitle(
  node: Pick<TreeTerminal, "terminal" | "info" | "pane">,
): string | null {
  const t = node.terminal;
  const name = node.info
    ? agentName(node.info, {
        name: t.name ?? undefined,
        report: t.report,
      })
    : t.name?.trim() || t.program?.name || t.address;
  return titleAfterProgram(programOf(node), name);
}

/**
 * A plain terminal's label: `programOf(node)`'s short name and its
 * `plainTitle`, two spaces apart ("fish  server"); without a name, its
 * folder as `folderOf` writes it with `home` ("fish  ~/x"). Without a short
 * program name, its name alone, else its address and folder.
 */
export function plainLabel(
  node: Pick<TreeTerminal, "terminal" | "info" | "pane">,
  home: string,
): string {
  const t = node.terminal;
  const program = programOf(node);
  const programName = shortProgramName(program);
  const title = plainTitle(node);
  if (t.name?.trim()) return labelOf(programName, title);

  const cwd = folderOf(t, home) ?? "";
  return programName === null
    ? [title, cwd].filter(Boolean).join("  ")
    : labelOf(programName, titleAfterProgram(program, cwd));
}

/**
 * A plain terminal's title: its trimmed name, null when that only names the
 * program (`titleAfterProgram`). Unnamed, null; but without a short program
 * name, the terminal's address, so the title still names it.
 */
function plainTitle(
  node: Pick<TreeTerminal, "terminal" | "info" | "pane">,
): string | null {
  const t = node.terminal;
  const program = programOf(node);
  const name = t.name?.trim();
  if (shortProgramName(program) === null) return name || t.address;
  return name ? titleAfterProgram(program, name) : null;
}

/**
 * What an agent row's third line says the agent is doing: its
 * `blockedKind`, else its `activity`, else its status word, so an agent's
 * row always has one.
 */
export function agentDoing(agent: AgentDoingSource): AgentDetail {
  const waitsFor = blockedKind(agent);
  if (waitsFor !== null) {
    return {
      kind: "blocked",
      text: waitsFor,
    };
  }
  if (agent.activity !== null) {
    return {
      kind: "activity",
      text: agent.activity,
    };
  }
  return {
    kind: "status",
    text: agent.status,
  };
}

/**
 * What a blocked agent waits for, as its report's `kind` word
 * ("permission", "question", "auth"); null unless `status` is "blocked",
 * since a report can keep a stale `kind` after the agent moves on.
 */
export function blockedKind(
  agent: Pick<AgentDoingSource, "status" | "reportKind">,
): string | null {
  return agent.status === "blocked" ? agent.reportKind : null;
}

/**
 * The fields of an agent row that `agentDoing` reads: its status word, its
 * report's `kind` (null when it gave none), and what it says it is doing now
 * (null when nothing).
 */
export interface AgentDoingSource {
  status: AgentStatus;
  reportKind: string | null;
  activity: string | null;
}

/**
 * `t`'s folder as a row shows it: the folder it is in now
 * (`foreground.cwd`, else the `cwd` it started in), with this computer's
 * `home` written as `~` (`homeRelative`) on this computer and unchanged on
 * another machine, whose home folder a view does not know. Null without
 * either folder.
 */
export function folderOf(t: TerminalEntry, home: string): string | null {
  const cwd = t.foreground?.cwd || t.cwd;
  if (!cwd) return null;
  return machineOf(t.address) ? cwd : homeRelative(cwd, home);
}

/** `path` with a leading `home` folder written as `~`. */
export function homeRelative(path: string, home: string): string {
  if (home === "") return path;
  if (path === home) return "~";
  return path.startsWith(`${home}/`) ? `~${path.slice(home.length)}` : path;
}

/**
 * What a label calls `program`, as a process list would: the program
 * table's key ("claude", "pi", "nvim"), or the process name ("fish", "make")
 * for a shell or a program the table doesn't list, whose keys ("shell",
 * "program", "agent") name no one program. Null without a program or a
 * name.
 */
function shortProgramName(program: Program | null): string | null {
  if (program === null) return null;
  const isGenericKey = GENERIC_PROGRAM_KEYS.includes(program.key);
  return (isGenericKey ? program.name : program.key) || null;
}

/**
 * The `Program.key`s the program table gives a shell or a program it does
 * not list, rather than one program.
 */
const GENERIC_PROGRAM_KEYS = ["shell", "program", "agent"];

/**
 * `name` as the title shown after `program`'s `shortProgramName`: null when
 * `name` is empty or only names the program (its short or full name,
 * ignoring case), and `name` unchanged without a short name.
 */
function titleAfterProgram(
  program: Program | null,
  name: string,
): string | null {
  const short = shortProgramName(program);
  if (short === null) return name;

  const lower = name.toLowerCase();
  const namesProgram =
    lower === "" ||
    lower === short.toLowerCase() ||
    lower === program?.name.toLowerCase();
  return namesProgram ? null : name;
}

/**
 * A label from its parts: `programName` and `title`, two spaces apart, or
 * whichever of them is not null.
 */
function labelOf(programName: string | null, title: string | null): string {
  return [programName, title].filter((part) => part !== null).join("  ");
}
