// The order views list spaces in (`spaceOrder`): the app's order, with each
// Git worktree's or jj workspace's space moved under the first space of its
// repo's main checkout. Also the checkout line under a space's name
// (`checkoutText`: "dotfiles / ws3").
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/space-order.ts` -> `../../mod-lib/space-order.ts`), and the
// herdr-app-mods build copies the file in place of the link and strips its
// types to `space-order.js`. The app refuses imports that leave a mod's own
// folder. It imports only types from `herdr`, so `mod-lib-test.mjs` can test
// it under Node.

import type { SpaceInfo } from "herdr";

// What ordering a space and naming its checkout need to know about the Git
// or jj checkout the space's folder is in: the repo's name, the checkout's
// root folder (`top`), its repo (an id equal for every checkout of one
// repo), and whether it is a linked worktree or secondary jj workspace
// rather than the repo's main checkout. The desk-spaces sidebar's
// `Checkout` holds these fields.
export interface SpaceCheckout {
  name: string;
  top: string;
  repo: string;
  linked: boolean;
}

// One space in `spaceOrder`'s order: the space, its checkout (null when not
// a repo or not known yet), and, for a linked checkout listed under its
// repo's main checkout, its branch mark ("├─", "└─" for the last), else null.
export interface OrderedSpace<S, C extends SpaceCheckout> {
  space: S;
  checkout: C | null;
  tree: "├─" | "└─" | null;
}

// `spaces` in their order, except that each space whose checkout
// (`checkoutOf`) is linked follows, marked, the first space of its repo
// whose checkout is the main one, with that repo's other linked spaces in
// their order. A linked space whose repo's main checkout has no space in
// `spaces` keeps its place, unmarked. Every space appears exactly once.
export function spaceOrder<S, C extends SpaceCheckout>(
  spaces: readonly S[],
  checkoutOf: (space: S) => C | null,
): OrderedSpace<S, C>[] {
  const list = spaces.map((space) => ({ space, checkout: checkoutOf(space) }));
  const mains = new Set(
    list.flatMap(({ checkout }) =>
      checkout && !checkout.linked ? [checkout.repo] : [],
    ),
  );
  const nested = ({ checkout }: (typeof list)[number]) =>
    Boolean(checkout?.linked && mains.has(checkout.repo));

  const out: OrderedSpace<S, C>[] = [];
  // Repos whose linked spaces are listed, under the first of its main spaces.
  const placed = new Set<string>();
  for (const entry of list) {
    if (nested(entry)) continue;
    out.push({ ...entry, tree: null });

    const { checkout } = entry;
    if (!checkout || checkout.linked || placed.has(checkout.repo)) continue;
    placed.add(checkout.repo);
    const kids = list.filter(
      (k) => nested(k) && k.checkout?.repo === checkout.repo,
    );
    kids.forEach((k, n) =>
      out.push({ ...k, tree: n === kids.length - 1 ? "└─" : "├─" }),
    );
  }
  return out;
}

// The text of the checkout line under space `space`'s name: the folder that
// `checkout` (or, outside a repo, the space's own folder) is named after,
// after its repo ("dotfiles / ws3", just "dotfiles" when they match,
// ignoring case); "~" at its machine's home, which an empty folder means,
// with `home` this computer's home folder. Null only when there is no folder
// to name (the filesystem root).
export function checkoutText(
  space: Pick<SpaceInfo, "folder" | "machine">,
  checkout: SpaceCheckout | null,
  home: string,
): string | null {
  const path = checkout ? checkout.top : space.folder;
  const folder = !path || (!space.machine && path === home) ? "~" : base(path);
  if (!folder) return null;
  if (!checkout) return folder;
  return checkout.name.toLowerCase() === folder.toLowerCase()
    ? checkout.name
    : `${checkout.name} / ${folder}`;
}

// The last segment of `path`, ignoring trailing slashes; empty for the
// filesystem root. (`split` always returns at least one element, so `pop`
// finds one.)
export const base = (path: string): string =>
  path.replace(/\/+$/, "").split("/").pop()!;
