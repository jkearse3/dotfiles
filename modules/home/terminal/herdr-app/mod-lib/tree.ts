// One tree of the app's live terminals (`buildTree`): machine, then space,
// then tab, then terminal, with each terminal's sub-terminals nested under
// it and the terminals no space holds set apart as each machine's
// elsewhere. It also gives the rule that decides which space a terminal
// belongs to (`spaceMembership`), a space's top-level terminals
// (`spaceTerminals`), whether a view folds a settled tab away (`tabFolded`),
// the status a terminal's row shows (`rowStatus`) and a depth-first walk
// giving each row its depth (`walkTree`). Finished terminals
// (`FinishedTerminal`) hang under the live terminal that started them.
//
// The tree is data only, in the app's layout order. It draws nothing,
// ranks nothing by urgency and does not nest a worktree's space under its
// repository's; each view that shows the tree does those itself. The
// desk-spaces sidebar lists it.
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/tree.ts` -> `../../mod-lib/tree.ts`), and the herdr-app-mods
// build copies the file in place of the link and strips its types to
// `tree.js`. The app refuses imports that leave a mod's own folder; the
// `./terminals.js`, `./status.js` and `./finished.js` this file imports, and
// the `./space-order.js` that `finished.js` imports, must be linked beside
// it too. It imports only types from `herdr`, so `mod-lib-test.mjs` can test
// it under Node.

import type { AgentInfo, PaneInfo, SpaceInfo, TabInfo } from "herdr";
import { finishedOutcome } from "./finished.js";
import type { FinishedTerminal } from "./finished.js";
import { kidStatus } from "./status.js";
import type { AgentStatus } from "./status.js";
import { MAX_ANCESTORS, machineOf, parentAddress } from "./terminals.js";
import type { TerminalEntry } from "./terminals.js";

// The app's data a tree is built from, read once per render.
export interface TreeWorld {
  // `terminals()`, in its order.
  terminals: TerminalEntry[];
  agents: AgentInfo[];
  // `panes()`, in its order.
  panes: PaneInfo[];
  // `spaces()`, in its order.
  spaces: SpaceInfo[];
  // The `machines` of `hc machine ls --json`, in any order.
  machines: MachineEntry[];
  // The finished terminals known, in any order.
  finished: FinishedTerminal[];
}

// The fields of an `hc machine ls --json` machine that a tree reads.
export interface MachineEntry {
  // What this computer calls it: `rohan` in `rohan/t7`.
  name: string;
  // connecting, connected, needs_login or unreachable.
  state: string;
  // Since when it is not connected, in ms since the epoch; null or missing
  // while connected.
  since_ms?: number | null;
  // A machine someone reached for one command; trees leave it out.
  temporary?: boolean;
}

// The app's live terminals as one tree (`buildTree`).
export interface Tree {
  // This computer first, then other machines by name.
  machines: TreeMachine[];
}

// A machine, the spaces that live on it and its terminals no space holds.
export interface TreeMachine {
  // Its `hc machine ls` name; null for this computer.
  name: string | null;
  // Its `hc machine ls` state; null for this computer, and for a machine
  // that a space or an elsewhere terminal names but `hc machine ls` does
  // not list.
  state: string | null;
  // Since when it is not connected, in ms since the epoch; null while
  // connected and whenever `state` is null.
  sinceMs: number | null;
  // Its spaces, in `spaces()` order; empty when it has none.
  spaces: TreeSpace[];
  // Its live terminals no space holds (`spaceMembership` gives none), by
  // `machineOf` their address, in `terminals()` order, with their
  // sub-terminals nested; empty when it has none.
  elsewhere: TreeTerminal[];
}

// A space and the live terminals that belong to it.
export interface TreeSpace {
  space: SpaceInfo;
  // Every tab of the space in its order, including empty and settled ones.
  tabs: TreeTab[];
  // The top-level terminals that belong to the space but show in none of
  // its tabs (no pane, so they belong by a label or an ancestor), in
  // `terminals()` order.
  loose: TreeTerminal[];
}

// A tab and the top-level terminals shown in it.
export interface TreeTab {
  tab: TabInfo;
  // The terminals whose first pane in `panes()` order is in this tab, in
  // that pane order; a terminal shown in two panes is listed once. Mod panes
  // hold no terminal and give none. A terminal nested under its parent is
  // listed there instead.
  terminals: TreeTerminal[];
}

// A live terminal in a tree.
export interface TreeTerminal {
  terminal: TerminalEntry;
  // Its `agents()` entry; null for a plain terminal or a paneless agent.
  info: AgentInfo | null;
  // Its first pane in `panes()` order; null without one.
  pane: PaneInfo | null;
  // An agent's own status: its `agents()` status when it has a pane, else
  // `kidStatus` of its `terminals()` status word. Null for a terminal that
  // reports no status.
  status: AgentStatus | null;
  // `machineOf(terminal.address)`.
  machine: string | null;
  // The live terminals whose parent is this one and that belong to the same
  // space (or, like it, to none), in `terminals()` order, wherever their
  // panes are.
  children: TreeTerminal[];
  // The finished terminals whose parent is this one, oldest `finishedMs`
  // first, for a view to list after its children.
  finished: FinishedTerminal[];
}

// The app's live terminals (`state` "live") as a tree:
// - Machines: this computer, then every non-temporary machine `hc machine
//   ls` lists and every machine a space or an elsewhere terminal names, by
//   name.
// - A terminal belongs to the space `spaceMembership` gives, or else to its
//   machine's elsewhere.
// - A terminal nests under its parent when the parent is live and belongs to
//   the same space (or, like it, to none), even when they show in different
//   tabs. On a parent cycle, the first member in `terminals()` order stays at
//   the top level and the others nest under it.
// - A finished terminal hangs under its parent when that is live, wherever
//   the parent is; one whose parent is not live is left out.
// - A top-level terminal goes in the tab of its first pane, or in its
//   space's `loose` when that pane is in none of the space's tabs.
export function buildTree(world: TreeWorld): Tree {
  const spaceOf = spaceMembership(world);
  const position = new Map(world.terminals.map((t, i) => [t.address, i]));
  const infoByAddress = new Map(world.agents.map((a) => [a.address, a]));
  const listed = new Map(world.agents.map((a) => [a.address, a.status]));
  const firstPanes = firstPaneByTerminal(world.panes);
  const paneIndex = new Map(world.panes.map((p, i) => [p, i]));

  const live = world.terminals.filter((t) => t.state === "live");
  const liveByAddress = new Map(live.map((t) => [t.address, t]));
  // The live terminal `t` nests under: its parent, when that is live and
  // belongs to the same space.
  const nestParentOf = (t: TerminalEntry): TerminalEntry | null => {
    const address = parentAddress(t);
    const parent = address ? liveByAddress.get(address) : undefined;
    return parent && spaceOf(parent) === spaceOf(t) ? parent : null;
  };
  const childrenByParent = new Map<string, TerminalEntry[]>();
  for (const t of live) {
    const parent = nestParentOf(t);
    if (!parent) continue;
    const siblings = childrenByParent.get(parent.address) ?? [];
    siblings.push(t);
    childrenByParent.set(parent.address, siblings);
  }
  const finishedByParent = new Map<string, FinishedTerminal[]>();
  for (const f of [...world.finished].sort(
    (x, y) => x.finishedMs - y.finishedMs,
  )) {
    if (f.parent === null) continue;
    const siblings = finishedByParent.get(f.parent) ?? [];
    siblings.push(f);
    finishedByParent.set(f.parent, siblings);
  }

  // Builds the subtree under `t`, skipping terminals already placed, so a
  // parent cycle cannot recurse forever.
  const placed = new Set<string>();
  const build = (t: TerminalEntry): TreeTerminal => {
    placed.add(t.address);
    const isAgent = typeof t.status === "string" && t.status !== "";
    const info = infoByAddress.get(t.address) ?? null;
    const children = (childrenByParent.get(t.address) ?? [])
      .filter((c) => !placed.has(c.address))
      .map(build);
    return {
      terminal: t,
      info,
      pane: firstPanes.get(t.address) ?? null,
      status:
        info?.status ??
        (isAgent
          ? kidStatus(
              { address: t.address, status: t.status as string },
              listed,
            )
          : null),
      machine: machineOf(t.address),
      children,
      finished: finishedByParent.get(t.address) ?? [],
    };
  };
  const tops: TreeTerminal[] = [];
  for (const t of live) if (!nestParentOf(t)) tops.push(build(t));
  // A terminal the walk never reached sits on a parent cycle: the first one
  // in `terminals()` order goes at the top level.
  for (const t of live) if (!placed.has(t.address)) tops.push(build(t));
  tops.sort(
    (x, y) =>
      (position.get(x.terminal.address) as number) -
      (position.get(y.terminal.address) as number),
  );

  const treeSpaces = new Map(
    world.spaces.map((space): [string, TreeSpace] => [
      space.id,
      {
        space,
        tabs: space.tabs.map((tab) => ({
          tab,
          terminals: [],
        })),
        loose: [],
      },
    ]),
  );
  const elsewhere: TreeTerminal[] = [];
  for (const node of tops) {
    const space = spaceOf(node.terminal);
    const treeSpace = space ? treeSpaces.get(space.id) : undefined;
    if (!treeSpace) {
      elsewhere.push(node);
      continue;
    }
    const tab = treeSpace.tabs.find((tt) => tt.tab.id === node.pane?.tab);
    (tab ? tab.terminals : treeSpace.loose).push(node);
  }
  for (const treeSpace of treeSpaces.values()) {
    for (const tab of treeSpace.tabs) {
      tab.terminals.sort(
        (x, y) =>
          (paneIndex.get(x.pane as PaneInfo) as number) -
          (paneIndex.get(y.pane as PaneInfo) as number),
      );
    }
  }

  return {
    machines: treeMachines(world, [...treeSpaces.values()], elsewhere),
  };
}

// The top-level terminals of `treeSpace`: each tab's in tab order, then its
// `loose` ones. Their sub-terminals stay nested under them.
export function spaceTerminals(treeSpace: TreeSpace): TreeTerminal[] {
  return [
    ...treeSpace.tabs.flatMap((tab) => tab.terminals),
    ...treeSpace.loose,
  ];
}

// Whether a view folds `treeTab` away, showing its divider without its
// terminal rows: true when the tab is settled (`TabInfo.settled`) and
// nothing in it, at any depth, needs the person: no terminal is blocked or
// done and no finished terminal failed (`finishedOutcome`). A tab that is
// not settled never folds.
export function tabFolded(treeTab: TreeTab): boolean {
  if (!treeTab.tab.settled) return false;
  for (const step of walkTree(treeTab.terminals)) {
    const needsYou =
      step.kind === "terminal"
        ? step.node.status === "blocked" || step.node.status === "done"
        : finishedOutcome(step.finished).failed;
    if (needsYou) return false;
  }
  return true;
}

// The status a terminal's row shows: its tree status, except that an agent
// nested under another agent (`parent`, null at the top level) is never
// done: it reports to its parent, and the parent's done is the news. Null
// for a terminal reporting no status.
export function rowStatus(
  node: TreeTerminal,
  parent: TreeTerminal | null,
): AgentStatus | null {
  const reportsToAgent = parent !== null && parent.status !== null;
  return reportsToAgent && node.status === "done" ? "idle" : node.status;
}

// `nodes` and every terminal nested under them, depth first, each parent
// before its children, then its finished terminals (`TreeStep`).
export function* walkTree(nodes: TreeTerminal[]): Generator<TreeStep> {
  yield* walkFrom(nodes, 0);
}

// One row on a `walkTree` walk: a live terminal or a finished one under its
// live parent.
export type TreeStep = TreeTerminalStep | TreeFinishedStep;

// A live terminal on a `walkTree` walk.
export interface TreeTerminalStep extends TreePlace {
  kind: "terminal";
  node: TreeTerminal;
}

// A finished terminal on a `walkTree` walk, after its parent's children.
export interface TreeFinishedStep extends TreePlace {
  kind: "finished";
  finished: FinishedTerminal;
  // The live terminal it hangs under.
  parent: TreeTerminal;
}

// Where a `TreeStep` sits in the walk.
export interface TreePlace {
  // 0 for one of the nodes the walk started from, 1 for its child, and so on.
  depth: number;
}

// `walkTree` below `nodes`, then the finished terminals `finished` of their
// parent `parent` (none at the top level), all at `depth`.
function* walkFrom(
  nodes: TreeTerminal[],
  depth: number,
  parent: TreeTerminal | null = null,
  finished: FinishedTerminal[] = [],
): Generator<TreeStep> {
  for (const node of nodes) {
    yield {
      kind: "terminal",
      node,
      depth,
    };
    yield* walkFrom(node.children, depth + 1, node, node.finished);
  }
  if (parent === null) return;
  for (const f of finished) {
    yield {
      kind: "finished",
      finished: f,
      parent,
      depth,
    };
  }
}

// This computer, then the non-temporary `world.machines` and the machines
// `spaces` and `elsewhere` name, by name, each holding its spaces and its
// elsewhere terminals in their order.
function treeMachines(
  world: TreeWorld,
  spaces: TreeSpace[],
  elsewhere: TreeTerminal[],
): TreeMachine[] {
  const byName = new Map<string, TreeMachine>();
  for (const m of world.machines) {
    if (m.temporary) continue;
    byName.set(m.name, {
      name: m.name,
      state: m.state,
      sinceMs: m.since_ms ?? null,
      spaces: [],
      elsewhere: [],
    });
  }

  const thisComputer: TreeMachine = {
    name: null,
    state: null,
    sinceMs: null,
    spaces: [],
    elsewhere: [],
  };
  // The entry of machine `name` (null for this computer), added without a
  // state when `hc machine ls` does not list it.
  const machineNamed = (name: string | null): TreeMachine => {
    if (name === null) return thisComputer;
    let machine = byName.get(name);
    if (!machine) {
      machine = {
        name,
        state: null,
        sinceMs: null,
        spaces: [],
        elsewhere: [],
      };
      byName.set(name, machine);
    }
    return machine;
  };
  for (const s of spaces) machineNamed(s.space.machine).spaces.push(s);
  for (const node of elsewhere) machineNamed(node.machine).elsewhere.push(node);

  const others = [...byName.values()].sort((x, y) =>
    (x.name as string).localeCompare(y.name as string),
  );
  return [thisComputer, ...others];
}

// The rule that decides which space a terminal belongs to, as a function of
// one terminal: walking from it up its `parent` links (`parentAddress`,
// through ended terminals too), the first terminal whose first pane in
// `panes()` order is in a space's tab gives that space, as does the first
// whose `herdr.space` label names a space (qualified with that terminal's
// machine when bare). Null (elsewhere) when none does within `MAX_ANCESTORS`
// steps. Each terminal's walk runs once per returned function.
export function spaceMembership(
  world: Pick<TreeWorld, "terminals" | "panes" | "spaces">,
): (t: TerminalEntry) => SpaceInfo | null {
  const byAddress = new Map(world.terminals.map((t) => [t.address, t]));
  const firstPanes = firstPaneByTerminal(world.panes);
  const spaceByTab = new Map(
    world.spaces.flatMap((s) => s.tabs.map((tab) => [tab.id, s] as const)),
  );
  const spaceById = new Map(world.spaces.map((s) => [s.id, s]));

  const walkToSpace = (t: TerminalEntry): SpaceInfo | null => {
    let current: TerminalEntry | undefined = t;
    for (let step = 0; current && step <= MAX_ANCESTORS; step++) {
      const pane = firstPanes.get(current.address);
      const paneSpace = pane ? spaceByTab.get(pane.tab) : undefined;
      if (paneSpace) return paneSpace;

      const label = current.labels?.["herdr.space"];
      if (label) {
        const machine = machineOf(current.address);
        const id =
          machine && !label.includes("/") ? `${machine}/${label}` : label;
        const labelSpace = spaceById.get(id);
        if (labelSpace) return labelSpace;
      }

      const parent = parentAddress(current);
      current = parent ? byAddress.get(parent) : undefined;
    }
    return null;
  };

  const spaceByAddress = new Map<string, SpaceInfo | null>();
  return (t) => {
    let space = spaceByAddress.get(t.address);
    if (space === undefined) {
      space = walkToSpace(t);
      spaceByAddress.set(t.address, space);
    }
    return space;
  };
}

// Each terminal's first pane in `panes` order, by address; mod panes hold no
// terminal and are left out.
function firstPaneByTerminal(panes: PaneInfo[]): Map<string, PaneInfo> {
  const first = new Map<string, PaneInfo>();
  for (const p of panes) {
    if (p.terminal !== null && !first.has(p.terminal)) first.set(p.terminal, p);
  }
  return first;
}
