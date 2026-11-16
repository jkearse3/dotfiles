// The desk-spaces sidebar's agents: the agents that need you (`needsYou`)
// and each agent's status and activity history (`AgentHistory`). How urgent
// a status is (`RANK`) lives in `status.ts`, and when a working agent counts
// as quiet (`quietFor`) in `quiet.ts`.

import type { AgentInfo, Status } from "herdr";
import { RANK } from "./status.js";
import type { TerminalEntry } from "./terminals.js";

// The agents of `list` that need you: those ranking done or above by `rank`
// (an agent -> its `RANK` value), most urgent first, newest first within a
// rank (higher `seq`), otherwise in `list` order. "Needs you" draws them by
// status; the next/previous order ranks by `orderRank`.
export const needsYou = (
  list: AgentInfo[],
  rank: (a: AgentInfo) => number,
): AgentInfo[] =>
  list
    .filter((a) => rank(a) >= RANK.done)
    .sort((x, y) => rank(y) - rank(x) || y.seq - x.seq);

// When each agent's status last changed (`track`, `since`), for the time its
// row shows, when each agent last showed activity (`trackActivity`,
// `activeAt`), for whether its row reads quiet, and the focused agent's held
// rank (`hold`, `orderRank`), for the next/previous order.
export class AgentHistory {
  declare changed: Record<string, StatusChange>;
  declare active: Record<string, Activity>;
  declare held: HeldRank | null;

  constructor() {
    // Each agent's last state and when it changed (ms), kept across restarts.
    this.changed = JSON.parse(
      localStorage.getItem("changed") ?? "{}",
    ) as Record<string, StatusChange>;
    // Each agent's last seen activity and when it changed (ms), kept across
    // restarts.
    this.active = JSON.parse(localStorage.getItem("active") ?? "{}") as Record<
      string,
      Activity
    >;
    // The focused agent and its rank when it got focus (see `hold`), or null.
    this.held = null;
  }

  // Stamps agents whose state changed. Done and idle count as one: looking at a
  // finished agent turns done into idle, and looking isn't the agent doing
  // anything.
  track(list: AgentInfo[], now: number): void {
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
  since(a: AgentInfo): number {
    return this.changed[a.address]?.at ?? 0;
  }

  // Stamps the terminals of `entries` that report a status and whose
  // activity changed: a new state (done counted as idle, as `track` does) or
  // status time from the core (`status_ms`, so a state change between two
  // samples still counts), report message or turn. One seen for the first
  // time, or stored without one of these, is stamped `now`.
  // Like `track`, it drops agents gone from `entries` for over 30 days and
  // saves only when something changed.
  trackActivity(entries: TerminalEntry[], now: number): void {
    let dirty = false;
    for (const k of entries) {
      if (!k.status) continue;
      const s = k.status === "done" ? "idle" : k.status;
      const m = k.report?.msg ?? null;
      const n = typeof k.turn === "number" ? k.turn : null;
      const sm = typeof k.status_ms === "number" ? k.status_ms : null;
      const last = this.active[k.address];
      if (
        last &&
        last.s === s &&
        last.sm === sm &&
        last.m === m &&
        last.n === n
      )
        continue;
      this.active[k.address] = {
        s,
        sm,
        m,
        n,
        at: now,
      };
      dirty = true;
    }
    if (!dirty) return;
    const listed = new Set(entries.map((k) => k.address));
    for (const [k, a] of Object.entries(this.active))
      if (!listed.has(k) && now - a.at > 30 * 86400000) delete this.active[k];
    localStorage.setItem("active", JSON.stringify(this.active));
  }

  // When the agent at `address` last showed activity (ms, see
  // `trackActivity`), null when never seen.
  activeAt(address: string): number | null {
    return this.active[address]?.at ?? null;
  }

  // Remembers the focused agent's rank on arrival. Looking at a done agent
  // turns it idle; the remembered rank keeps it in its next/previous slot
  // until you leave it. Any other change takes the new rank at once.
  hold(list: AgentInfo[]): void {
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
  orderRank(a: AgentInfo): number {
    const sawDone =
      a.address === this.held?.address &&
      this.held.rank === RANK.done &&
      a.status === "idle";
    return sawDone ? RANK.done : (RANK[a.status] ?? 0);
  }
}

// An agent's last state (done counted as idle) and when it changed (ms).
interface StatusChange {
  s: Status;
  at: number;
}

// An agent's last seen activity: its state (`s`, done counted as idle), when
// the core says that state last changed (`sm`, ms since the epoch), its report
// message (`m`) and its turn count (`n`), each null when the core reports
// none, and when any of them last changed (`at`, ms).
interface Activity {
  s: string;
  sm: number | null;
  m: string | null;
  n: number | null;
  at: number;
}

// The focused agent's address and its `RANK` value when it got focus.
interface HeldRank {
  address: string;
  rank: number;
}
