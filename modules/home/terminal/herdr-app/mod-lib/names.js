// What to call an agent (`agentName`) and what it is doing now
// (`agentActivity`), whatever program it runs.
//
// The deploy tree copies this file into each mod folder that deploy.nix
// `sharedModFiles` lists, at build time, so edit it here rather than in a
// deployed copy. It is copied because the app refuses imports that leave a
// mod's own folder; `./names.js` beside the importing file is allowed.
//
// No one field names every agent. The status report's message (OSC 7501) is
// free text each agent fills its own way: Claude Code's is the step it is on
// now, pi's its session name. The terminal title is the agent's to set too:
// Claude Code titles itself after its topic, opencode as "OC | <session>",
// pi as "pi - <folder>". So each agent gets a rule in `TOPICS`, and the
// fallbacks are the same for all.

// Leading decoration (Claude Code's "✳ ", spinners) and surrounding spaces.
const clean = (s) => (s ?? "").replace(/^[^\p{L}\p{N}]+/u, "").trim();

// `text` cleaned when it says what the agent is on, else null: not when it is
// empty, only the program's name, a path, a shell's user@host, or the program
// and a folder ("pi - dotfiles").
function useful(text, a) {
  const s = clean(text);
  if (!s) return null;
  const program = [a.program?.name, a.program?.key, a.app, "π"]
    .filter(Boolean)
    .map((p) => p.toLowerCase());
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
const reportOf = (k) =>
  k?.report ?? (typeof k?.status === "object" ? k.status : null);

// Per agent, by the app it reports (`AgentInfo.app`): where it says its topic.
const TOPICS = {
  "claude-code": (a) => a.title,
  opencode: (a) => clean(a.title).replace(/^OC \| /, ""),
  // pi reports its session name (set with /name) while working or done.
  pi: (_a, k) => {
    const r = reportOf(k);
    return r && ["working", "done"].includes(r.state) ? r.msg : null;
  },
};

// The name to show for agent `a` (an `agents()` entry), given its `terminals()`
// entry `k` (may be undefined): its terminal's name when someone set one,
// else its own topic by its rule in `TOPICS`, else its title when that says
// something, else its program, else its address. Never its tab: that says
// where the agent is, which a mod shows apart from what the agent is.
export function agentName(a, k) {
  return (
    clean(k?.name) ||
    useful(TOPICS[a.app]?.(a, k), a) ||
    useful(a.title, a) ||
    a.program?.name ||
    a.address
  );
}

// Per agent, by the app it reports: where it says what it is doing now. Only
// agents whose report message is their current step have a rule; pi's
// message is its session name (`TOPICS`), so pi has none.
const ACTIVITIES = {
  "claude-code": (_a, k) => {
    const r = reportOf(k);
    return r?.state === "working" ? r.msg : null;
  },
};

// What agent `a` is doing now, by its rule in `ACTIVITIES` (given its
// `terminals()` entry `k`, which may be undefined), cleaned; null for an agent
// without a rule or one that isn't saying.
export function agentActivity(a, k) {
  return clean(ACTIVITIES[a.app]?.(a, k)) || null;
}
