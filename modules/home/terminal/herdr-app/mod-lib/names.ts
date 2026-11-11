// What to call an agent (`agentName`) and what it is doing now
// (`agentActivity`), whatever program it runs.
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/names.ts` -> `../../mod-lib/names.ts`), and the herdr-app-mods
// build copies the file in place of the link and strips its types to
// `names.js`. The app refuses imports that leave a mod's own folder;
// `./names.js` beside the importing file is allowed.
//
// No one field names every agent. The status report's message (OSC 7501) is
// free text each agent fills its own way: Claude Code's is the step it is on
// now, pi's its session name. The terminal title is the agent's to set too:
// Claude Code titles itself after its topic, opencode as "OC | <session>",
// pi as "pi - <folder>". So each agent gets a rule in `TOPICS`, and the
// fallbacks are the same for all.

import type { AgentInfo } from "herdr";

// The agent's status report (OSC 7501) as a `terminals()` entry carries it.
interface AgentReport {
  app?: string;
  state?: string;
  msg?: string;
}

// The fields of a `terminals()` entry these rules read: the name someone gave
// the terminal and the agent's report. The app's typings type the entries as
// `any`; `hc get` prints the report as `status` instead of `report`.
interface TerminalEntry {
  name?: string;
  report?: AgentReport;
  status?: string | AgentReport;
}

// One agent's rule for what it says about itself, given its `agents()` entry
// and its `terminals()` entry (may be undefined): the text, or null or
// undefined when it says nothing.
type AgentRule = (
  a: AgentInfo,
  k: TerminalEntry | undefined,
) => string | null | undefined;

// Leading decoration (Claude Code's "✳ ", spinners) and surrounding spaces.
const clean = (s: string | null | undefined): string =>
  (s ?? "").replace(/^[^\p{L}\p{N}]+/u, "").trim();

// `text` cleaned when it says what the agent is on, else null: not when it is
// empty, only the program's name, a path, a shell's user@host, or the program
// and a folder ("pi - dotfiles").
function useful(text: string | null | undefined, a: AgentInfo): string | null {
  const s = clean(text);
  if (!s) return null;
  const program = [a.program?.name, a.program?.key, a.app, "π"]
    // `filter(Boolean)` dropped the missing names.
    .filter(Boolean)
    .map((p) => p!.toLowerCase());
  const lower = s.toLowerCase();
  const head = lower.match(/^(\S+) [-–—|] \S+$/)?.[1];
  const quiet =
    program.includes(lower) ||
    (head && program.includes(head)) ||
    // The raw text: cleaning strips a path's leading "~/" or "/".
    /^[~/]|^[A-Za-z]:\\/.test((text ?? "").trim()) ||
    s.includes("@");
  return quiet ? null : s;
}

// The agent's report from `terminals()`: { app, state, msg }. The app's
// typings call it `report`; `hc get` prints the same object as `status`.
const reportOf = (k: TerminalEntry | undefined): AgentReport | null =>
  k?.report ?? (typeof k?.status === "object" ? k.status : null);

// Per agent, by the app it reports (`AgentInfo.app`): where it says its topic.
const TOPICS: Record<string, AgentRule> = {
  "claude-code": (a) => a.title,
  opencode: (a) => clean(a.title).replace(/^OC \| /, ""),
  // pi reports its session name (set with /name) while working or done.
  pi: (_a, k) => {
    const r = reportOf(k);
    return r &&
      (["working", "done"] as (string | undefined)[]).includes(r.state)
      ? r.msg
      : null;
  },
};

// The name to show for agent `a` (an `agents()` entry), given its `terminals()`
// entry `k` (may be undefined): its terminal's name when someone set one,
// else its own topic by its rule in `TOPICS`, else its title when that says
// something, else its program, else its address. Never its tab: that says
// where the agent is, which a mod shows apart from what the agent is.
export function agentName(a: AgentInfo, k: TerminalEntry | undefined): string {
  return (
    clean(k?.name) ||
    // An agent that reports no app (null) indexes as "null": no rule.
    useful(TOPICS[a.app as string]?.(a, k), a) ||
    useful(a.title, a) ||
    a.program?.name ||
    a.address
  );
}

// Per agent, by the app it reports: where it says what it is doing now. Only
// agents whose report message is their current step have a rule; pi's
// message is its session name (`TOPICS`), so pi has none.
const ACTIVITIES: Record<string, AgentRule> = {
  "claude-code": (_a, k) => {
    const r = reportOf(k);
    return r?.state === "working" ? r.msg : null;
  },
};

// What agent `a` is doing now, by its rule in `ACTIVITIES` (given its
// `terminals()` entry `k`, which may be undefined), cleaned; null for an agent
// without a rule or one that isn't saying.
export function agentActivity(
  a: AgentInfo,
  k: TerminalEntry | undefined,
): string | null {
  // An agent that reports no app (null) indexes as "null": no rule.
  return clean(ACTIVITIES[a.app as string]?.(a, k)) || null;
}
