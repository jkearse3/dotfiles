// The desk-spaces sidebar's agents: the agents that need you (`needsYou`)
// and each agent's status history (`AgentHistory`). How urgent a status is
// (`RANK`) lives in `status.ts`.

import type { AgentInfo, Status } from "herdr";
import { RANK } from "./status.js";

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
// row shows, and the focused agent's held rank (`hold`, `orderRank`), for the
// next/previous order.
export class AgentHistory {
  declare changed: Record<string, StatusChange>;
  declare held: HeldRank | null;

  constructor() {
    // Each agent's last state and when it changed (ms), kept across restarts.
    this.changed = JSON.parse(
      localStorage.getItem("changed") ?? "{}",
    ) as Record<string, StatusChange>;
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

// The focused agent's address and its `RANK` value when it got focus.
interface HeldRank {
  address: string;
  rank: number;
}
