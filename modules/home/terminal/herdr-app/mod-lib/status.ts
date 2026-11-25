// How urgent an agent's status is: the statuses a sidebar ranks
// (`AgentStatus`), their order (`RANK`), a sub-agent's status (`kidStatus`)
// and the most urgent of several (`topStatus`).
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/status.ts` -> `../../mod-lib/status.ts`), and the herdr-app-mods
// build copies the file in place of the link and strips its types to
// `status.js`. The app refuses imports that leave a mod's own folder;
// `./status.js` beside the importing file is allowed.

import type { Status } from "herdr";

/**
 * An agent status as the sidebar ranks it: an agent's `Status`, or a
 * sub-agent's raw word (`kidStatus`), which ranks below every status.
 */
export type AgentStatus = Status | string;

/**
 * `RANK` and `kidStatus` are copied from the shipped `agents` mod.
 * Statuses without an entry rank 0.
 */
export const RANK: Record<AgentStatus, number> = {
  blocked: 4,
  done: 3,
  working: 2,
  idle: 1,
};
/**
 * A sub-agent without a pane isn't in agents(): its raw word, error counting as
 * blocked. It's never done: it reports to its parent, and the parent's done is
 * the news.
 */
export const kidStatus = (
  k: { address: string; status: string },
  listed: Map<string, Status>,
): AgentStatus => {
  const s = listed.get(k.address) ?? k.status;
  return s === "error" ? "blocked" : s === "done" ? "idle" : s;
};

/**
 * The most urgent of `statuses` (blocked > done > working > idle), or null
 * when none ranks. A null status ranks as none.
 */
export const topStatus = (
  statuses: (AgentStatus | null)[],
): AgentStatus | null =>
  statuses.reduce<AgentStatus | null>(
    // A null status indexes as "null", which `RANK` lacks: it ranks 0.
    (top, s) =>
      (RANK[s as AgentStatus] ?? 0) > (RANK[top as AgentStatus] ?? 0) ? s : top,
    null,
  );
