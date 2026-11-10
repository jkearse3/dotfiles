// The desk-spaces sidebar's agents: each space's crew gathered from the app's
// agent list with sub-agents and names (`gatherAgents`), how urgent a status
// is (`RANK`, `topStatus`, `needsYou`), and each agent's status history
// (`AgentHistory`).

import { panes, terminals } from "herdr";
import { agentActivity, agentName } from "./names.js";

// `RANK` and `kidStatus` are copied from the shipped `agents` mod.
export const RANK = { blocked: 4, done: 3, working: 2, idle: 1 };
// A sub-agent without a pane isn't in agents(): its raw word, error counting as
// blocked. It's never done: it reports to its parent, and the parent's done is
// the news.
export const kidStatus = (k, listed) => {
  const s = listed.get(k.address) ?? k.status;
  return s === "error" ? "blocked" : s === "done" ? "idle" : s;
};

// The most urgent of `statuses` (blocked > done > working > idle), or null
// when none ranks.
export const topStatus = (statuses) =>
  statuses.reduce(
    (top, s) => ((RANK[s] ?? 0) > (RANK[top] ?? 0) ? s : top),
    null,
  );

// The agents of `list` that need you: those ranking done or above by `rank`
// (an agent -> its `RANK` value), most urgent first, newest first within a
// rank (higher `seq`), otherwise in `list` order. "Needs you" draws them by
// status; the next/previous order ranks by `orderRank`.
export const needsYou = (list, rank) =>
  list
    .filter((a) => rank(a) >= RANK.done)
    .sort((x, y) => rank(y) - rank(x) || y.seq - x.seq);

// Groups this render's agents (`list`, agents() order) by space, for spaces
// `sp`. Returns { byAddress, crews, listed }: every crew member by agent
// address, each space id's members in `list` order, and each listed agent's
// status by address (for `kidStatus`). Each crew member is { a, subs,
// status, label, spot, activity, turn }: `subs` its live sub-agents (`tree`),
// `status` the most urgent of its own and theirs, `label` what it is
// (`agentName`), `spot` where it is ({ tab, named, pane }: its tab's name,
// whether someone named it, and its place among the tab's panes in the app's
// pane order only when the tab holds more than one agent, else null),
// `activity` what it is doing now (`agentActivity`, or null), `turn` its turn
// count from the core (or null).
export function gatherAgents(list, sp) {
  const listed = new Map(list.map((a) => [a.address, a.status]));
  const all = terminals();
  const byTerminal = new Map(all.map((k) => [k.address, k]));
  const agentsPerTab = {};
  for (const a of list) agentsPerTab[a.tab] = (agentsPerTab[a.tab] ?? 0) + 1;
  const ps = panes();
  const tabs = new Map(sp.flatMap((s) => s.tabs ?? []).map((b) => [b.id, b]));
  const byAddress = new Map();
  const crews = new Map();
  for (const a of list) {
    const subs = tree(all, a.address);
    const status = topStatus([
      a.status,
      ...subs.map((s) => kidStatus(s.t, listed)),
    ]);
    const tab = tabs.get(a.tab);
    const term = byTerminal.get(a.address);
    const tabPanes = ps.filter((p) => p.tab === a.tab);
    const pane = tabPanes.findIndex((p) => p.pane === a.pane) + 1;
    const spot = {
      tab: tab?.name ?? a.tab_name ?? "",
      named: tab?.named ?? false,
      pane: agentsPerTab[a.tab] > 1 && pane > 0 ? pane : null,
    };
    const member = {
      a,
      subs,
      status,
      label: agentName(a, term),
      spot,
      activity: agentActivity(a, term),
      turn: term?.turn ?? null,
    };
    byAddress.set(a.address, member);
    if (!crews.has(a.space)) crews.set(a.space, []);
    crews.get(a.space).push(member);
  }
  return { byAddress, crews, listed };
}

// Live sub-agents of `addr`, depth first, each with the tree lines in front
// of it.
function tree(all, addr, lead = []) {
  const kids = all.filter((k) => k.parent === addr && k.state === "live");
  return kids.flatMap((k, i) => {
    const last = i === kids.length - 1;
    return [
      { t: k, lines: [...lead, last ? "└" : "├"] },
      ...tree(all, k.address, [...lead, last ? "" : "│"]),
    ];
  });
}

// When each agent's status last changed (`track`, `since`), for the time its
// row shows, and the focused agent's held rank (`hold`, `orderRank`), for the
// next/previous order.
export class AgentHistory {
  constructor() {
    // Each agent's last state and when it changed (ms), kept across restarts.
    this.changed = JSON.parse(localStorage.getItem("changed") ?? "{}");
    // The focused agent and its rank when it got focus (see `hold`), or null.
    this.held = null;
  }

  // Stamps agents whose state changed. Done and idle count as one: looking at a
  // finished agent turns done into idle, and looking isn't the agent doing
  // anything.
  track(list, now) {
    let dirty = false;
    for (const a of list) {
      const s = a.status === "done" ? "idle" : a.status;
      if (this.changed[a.address]?.s === s) continue;
      this.changed[a.address] = { s, at: now };
      dirty = true;
    }
    if (!dirty) return;
    // Gone and old: the list alone is empty right after a start.
    const listed = new Set(list.map((a) => a.address));
    for (const [k, c] of Object.entries(this.changed))
      if (!listed.has(k) && now - c.at > 30 * 86400000) delete this.changed[k];
    localStorage.setItem("changed", JSON.stringify(this.changed));
  }

  // When `a`'s status last changed (ms), 0 when never seen.
  since(a) {
    return this.changed[a.address]?.at ?? 0;
  }

  // Remembers the focused agent's rank on arrival. Looking at a done agent
  // turns it idle; the remembered rank keeps it in its next/previous slot
  // until you leave it. Any other change takes the new rank at once.
  hold(list) {
    const cur = list.find((a) => a.focused);
    const same = cur && cur.address === this.held?.address;
    if (!same || cur.status !== "idle")
      this.held = cur
        ? {
            address: cur.address,
            rank: RANK[cur.status] ?? 0,
          }
        : null;
  }

  // The rank an agent keeps in the next/previous order: a held agent that went
  // done to idle still ranks as done.
  orderRank(a) {
    const sawDone =
      a.address === this.held?.address &&
      this.held.rank === RANK.done &&
      a.status === "idle";
    return sawDone ? RANK.done : (RANK[a.status] ?? 0);
  }
}
