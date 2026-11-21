// Which badge the desk-spaces sidebar puts on a checkout line: "conflict"
// for a jj checkout with a conflict, "review" for unshipped work beside an
// agent with nothing left to do. `spaceCheckoutBadgeKind` decides it for a
// space's checkout line, `terminalCheckoutBadgeKind` for a terminal row's;
// `rows.ts` draws the chip.
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/checkout-badge.ts` -> `../../mod-lib/checkout-badge.ts`), and
// the herdr-app-mods build copies the file in place of the link and strips
// its types to `checkout-badge.js`. The app refuses imports that leave a
// mod's own folder. It imports only types, so `mod-lib-test.mjs` can test it
// under Node.

import type { AgentStatus } from "./status.js";

// A checkout badge: "conflict" when @ of a jj checkout has a conflict,
// "review" when the checkout has unshipped work to look over.
export type CheckoutBadgeKind = "conflict" | "review";

// What the badge needs to know about a checkout. The desk-spaces sidebar's
// `Checkout` (`JjCheckout` or `GitCheckout`) holds these fields: for jj,
// whether @ has a conflict or edits, and which way and how far @ is from
// the nearest bookmark, counting @ itself; for Git, how many commits it is
// ahead of its upstream.
export type BadgeCheckout =
  | {
      jj: true;
      conflict: boolean;
      modified: boolean;
      direction: "↓" | "↑";
      distance: number;
    }
  | {
      jj?: false;
      ahead: number;
    };

// The badge for a space's checkout line, by the statuses of the space's
// agents (`agentStatuses`) and its checkout `g` (null when not a repo or not
// known yet): only for a quiet space, one with agents and none working or
// blocked, "conflict" when its jj checkout has one, else "review" for
// unshipped work. Null otherwise, and always for a space without agents.
export function spaceCheckoutBadgeKind(
  agentStatuses: AgentStatus[],
  g: BadgeCheckout | null,
): CheckoutBadgeKind | null {
  const quiet =
    agentStatuses.length > 0 &&
    !agentStatuses.some((s) => s === "working" || s === "blocked");
  return g && quiet ? checkoutBadgeKind(g, true) : null;
}

// The badge for a terminal row's checkout line, by the terminal's agent
// status (`status`, null for a plain terminal) and checkout `g`: "conflict"
// on every row whose jj checkout has one, whatever the terminal is doing;
// else "review" for unshipped work, only on an agent that is neither working
// nor blocked, since the tail's yellow ● already marks edits on every row.
// Null otherwise.
export function terminalCheckoutBadgeKind(
  status: AgentStatus | null,
  g: BadgeCheckout,
): CheckoutBadgeKind | null {
  const reviewable =
    status !== null && status !== "working" && status !== "blocked";
  return checkoutBadgeKind(g, reviewable);
}

// Which badge checkout `g` earns: "conflict" when its jj checkout has one,
// else, when `reviewable`, "review" for unshipped work (jj: edits in @ or
// revisions after the nearest bookmark; git: commits ahead of upstream).
// Null otherwise.
function checkoutBadgeKind(
  g: BadgeCheckout,
  reviewable: boolean,
): CheckoutBadgeKind | null {
  if (g.jj && g.conflict) return "conflict";
  const unshipped = g.jj
    ? // The jj distance counts @ itself, whose content `modified` covers.
      g.modified || (g.direction === "↑" && g.distance > 1)
    : g.ahead > 0;
  return reviewable && unshipped ? "review" : null;
}
