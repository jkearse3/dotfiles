// Whether the desk-spaces sidebar puts a "review" badge on a terminal row's
// checkout line, for unshipped work beside an agent with nothing left to do.
// `terminalCheckoutNeedsReview` decides it; `rows.ts` draws the chip.
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/checkout-badge.ts` -> `../../mod-lib/checkout-badge.ts`), and
// the herdr-app-mods build copies the file in place of the link and strips
// its types to `checkout-badge.js`. The app refuses imports that leave a
// mod's own folder. It imports only types, so `mod-lib-test.mjs` can test it
// under Node.

import type { AgentStatus } from "./status.js";

/**
 * What the badge needs to know about a checkout. The desk-spaces sidebar's
 * `Checkout` (`JjCheckout` or `GitCheckout`) holds these fields: for jj,
 * whether `@` has a conflict or edits, and which way and how far `@` is from
 * the nearest bookmark, counting `@` itself; for Git, how many commits it is
 * ahead of its upstream.
 */
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

/**
 * Whether a terminal row's checkout line gets the "review" badge, by the
 * terminal's agent status (`status`, null for a plain terminal) and checkout
 * `g`: true for unshipped work (jj: edits in `@` or revisions after the
 * nearest bookmark; git: commits ahead of upstream), only on an agent that
 * is neither working nor blocked, since the tail's yellow ● already marks
 * edits on every row. Never on a jj checkout with a conflict: the tail's
 * red × marks that on every row, and the conflict needs resolving before
 * review.
 */
export function terminalCheckoutNeedsReview(
  status: AgentStatus | null,
  g: BadgeCheckout,
): boolean {
  const reviewable =
    status !== null && status !== "working" && status !== "blocked";
  if (!reviewable || (g.jj && g.conflict)) return false;
  return g.jj
    ? // The jj distance counts @ itself, whose content `modified` covers.
      g.modified || (g.direction === "↑" && g.distance > 1)
    : g.ahead > 0;
}
