// The find hub's rows, in the order it shows them with an empty query
// (`findRows`): the space tree `tree.ts` builds, in the app's layout order.
// Each machine, this computer first, heads its spaces and then its
// "elsewhere" label over the terminals no space holds. A machine's spaces
// list in `spaceOrder`'s order, each Git worktree's or jj workspace's space
// under its repo's main checkout, by the checkouts the desk-spaces sidebar
// shares; each space heads a divider for each of its tabs, each followed by
// that tab's terminals in pane order with sub-terminals nested under their
// parents; then come the rows
// that make a new terminal or space. An agent is a terminal that reports a
// status, so agents and plain terminals share one `terminal` row kind; a
// plain terminal whose foreground runs a command rather than its shell
// (`runningCommand` in `foreground.ts`) shows that command on its row's
// third line, which a query does not match. After
// a terminal's nested rows come the terminals it started that have finished
// (`finished` rows), oldest first. The terminal and finished rows of a
// folded tab (`tabFolded`: settled, with nothing in it needing the person)
// are listed for a query to match, but marked `folded`, and `unfoldedRows`
// leaves them out of the empty query's list. `needsYouRows` keeps only the
// terminal rows showing blocked or done and the finished rows that failed,
// for the hub's needs-you filter.
//
// The rows are a pure function of the app's data, passed in as a
// `FindWorld`, so `find-test.mjs` can test them under Node. This file therefore
// imports only types from `herdr`; `status.ts`, `names.ts`, `terminals.ts`,
// `tree.ts`, `space-order.ts`, `finished.ts`, `foreground.ts` and
// `labels.ts` beside it are links to the shared copies in `mod-lib/`.

import type { AgentInfo, PaneInfo, SpaceInfo, TabInfo } from "herdr";
import { finishedLabel, finishedOutcome } from "./finished.js";
import type { FinishedTerminal } from "./finished.js";
import { runningCommand } from "./foreground.js";
import { agentLabel, folderOf, terminalRowModel } from "./labels.js";
import type { TerminalRowModel } from "./labels.js";
import { checkoutText, spaceOrder } from "./space-order.js";
import type { SpaceCheckout } from "./space-order.js";
import type { AgentStatus } from "./status.js";
import { machineOf, parentAddress } from "./terminals.js";
import type { TerminalEntry } from "./terminals.js";
import { buildTree, rowStatus, tabFolded, walkTree } from "./tree.js";
import type {
  MachineEntry,
  TreeFinishedStep,
  TreeMachine,
  TreeTerminal,
  TreeTerminalStep,
} from "./tree.js";

/** The app's data the hub's rows are built from, read once per render. */
export interface FindWorld {
  /** `terminals()`, in its order. */
  terminals: TerminalEntry[];
  agents: AgentInfo[];
  panes: PaneInfo[];
  /**
   * `spaces()`, in its order, which the hub lists each machine's spaces in,
   * apart from the nesting `checkouts` gives.
   */
  spaces: SpaceInfo[];
  /**
   * Each space's checkout by space id, as the desk-spaces sidebar shares it
   * (`readSpaceCheckouts` of `shared(SPACE_CHECKOUTS_KEY)`): null for a
   * space whose folder is in no repo. A space left out, or every space when
   * the whole value is null, has no checkout line and is not nested.
   */
  checkouts: Record<string, SpaceCheckout | null> | null;
  /**
   * The `machines` of `hc machine ls --json`, read when the hub opens; empty
   * until that answers or when it fails.
   */
  machines: MachineEntry[];
  /**
   * The finished terminals known (`buildTree` hangs each under its live
   * parent, and the hub lists each as a `finished` row).
   */
  finished: FinishedTerminal[];
  /**
   * `home()`: this computer's home folder, written as `~` in plain
   * terminals' labels.
   */
  home: string;
}

/**
 * One row of the hub. `key` is unique among a `findRows` result and never
 * shown; `text` is the row's visible text, the only text a query matches.
 */
export type FindRow =
  | {
      kind: "terminal";
      /** `a:<address>`. */
      key: string;
      /**
       * Its `model`'s program name, title, status word, blocked kind and
       * folder, as its row draws them, then its space's name (or
       * "elsewhere") and its machine, so a query can match a terminal by
       * its program, such as "claude" or "fish", an agent by the status its
       * row shows, such as "blocked" or "done", a blocked agent by what it
       * waits for, such as "permission", or a terminal by a segment of the
       * folder its row shows.
       */
      text: string;
      address: string;
      /**
       * What its row shows (`terminalRowModel` from `labels.ts`), drawn by
       * `terminalRow` from `tree-rows.ts`. An agent's status is `rowStatus`
       * of its tree status (`TreeTerminal.status`). A plain terminal's label
       * repeated within its space ends with an ordinal ("fish  ~/x  #2"),
       * which its title, as the row draws it, ends with too ("#2" alone
       * without a title). A plain terminal running a command has it as its
       * `detail`, without a start time.
       */
      model: TerminalRowModel;
      /**
       * When an agent's status last changed, in ms since the epoch: its
       * `terminals()` entry's `status_ms`. Null while it works, when its
       * spinner says so, when unknown, and for a plain terminal.
       */
      since: number | null;
      /**
       * 0 at the top level of its space or of an elsewhere label, its
       * parent's depth + 1 for a terminal nested under its parent.
       */
      depth: number;
      /**
       * The label of the terminal it is nested under; at the top level, its
       * parent's label when that is listed under another header or is an
       * agent that ended, else null.
       */
      parentLabel: string | null;
      /**
       * "no pane" for a terminal without a pane listed after its space's
       * tabs or under an elsewhere label; else null.
       */
      note: string | null;
      /** The space it is listed under; null under an elsewhere label. */
      space: SpaceInfo | null;
      /** `machineOf(address)`. */
      machine: string | null;
      /** The tab of its first pane in `panes()` order, or null without one. */
      tab: string | null;
      /**
       * That tab's position in its space, from 1 (`TabInfo.index`); null
       * without a pane, or when no space in `spaces()` holds the tab.
       */
      tabIndex: number | null;
      /**
       * Its first pane's position among its tab's panes in `panes()` order,
       * from 1, counting mod panes, which take a place in the tab like any
       * other; null without a pane.
       */
      paneIndex: number | null;
      /**
       * `folderOf` the terminal: its current folder, with this computer's
       * home as `~`; null when it reports no folder.
       */
      folder: string | null;
      /**
       * Whether it is listed under a folded tab (`tabFolded`: settled, with
       * nothing in it needing the person), whose divider shows without its
       * terminal rows while the query is empty; a query still matches it.
       */
      folded: boolean;
    }
  | {
      /**
       * A finished terminal, listed after the live terminals nested under
       * the live terminal that started it, drawn by `finishedRow` from
       * `tree-rows.ts`. Enter goes to that live terminal.
       */
      kind: "finished";
      /** `f:<address>`. */
      key: string;
      /**
       * Its label (`finishedLabel`), how it ended (`finishedOutcome`'s
       * text, such as "exit 1"), the word "finished", its space's name (or
       * "elsewhere") and its machine, so a query such as "finished" or
       * "exit 1" finds it.
       */
      text: string;
      finished: FinishedTerminal;
      /** The address of the live terminal it is listed under. */
      parent: string;
      /**
       * That terminal's label (`TerminalRowModel.label`), which names it on a
       * flat list's row, where indentation doesn't show it.
       */
      parentLabel: string;
      /**
       * The tab of that terminal's first pane in `panes()` order; null when
       * it has no pane, so Enter peeks at it instead.
       */
      parentTab: string | null;
      /** Its parent's depth + 1. */
      depth: number;
      /** The space it is listed under; null under an elsewhere label. */
      space: SpaceInfo | null;
      /** `machineOf(finished.address)`. */
      machine: string | null;
      /**
       * Whether it is listed under a folded tab (`tabFolded`), as a
       * terminal row's `folded`.
       */
      folded: boolean;
    }
  | {
      /**
       * The divider that starts a tab's rows, drawn by `tabDivider` from
       * `tree-rows.ts` and dimmed while the tab is settled; never selected,
       * and dropped while filtering.
       */
      kind: "tab";
      /** `t:<id>`. */
      key: string;
      /** The tab's name; never shown or matched. */
      text: string;
      tab: TabInfo;
      /** The space the tab is in. */
      space: SpaceInfo;
    }
  | {
      /**
       * A machine's header, drawn by `machineHeader` from `tree-rows.ts`;
       * never selected, and dropped while filtering.
       */
      kind: "machine";
      /** `m:<name>`, or "m:" for this computer. */
      key: string;
      /** Its name, or "this computer". */
      text: string;
      /** What its header shows; the rows under it carry the rest. */
      machine: Pick<TreeMachine, "name" | "state" | "sinceMs">;
    }
  | {
      kind: "space";
      /** `s:<id>`. */
      key: string;
      /**
       * Its name and machine, then its checkout line, so a query such as
       * "ws3" matches the space of a checkout by its workspace's name.
       */
      text: string;
      space: SpaceInfo;
      /**
       * The line under its name: `checkoutText` of its shared checkout
       * ("dotfiles / ws3"); null when `FindWorld.checkouts` has no entry for
       * it or there is no folder to name.
       */
      checkoutLine: string | null;
      /**
       * Its branch mark ("├─", "└─" for the last) when it is listed under its
       * repo's main checkout (`spaceOrder`), else null.
       */
      tree: "├─" | "└─" | null;
    }
  | {
      /**
       * The label over a machine's terminals no space holds; never
       * selected, and dropped while filtering.
       */
      kind: "elsewhere";
      /** `elsewhere:<machine>`, or "elsewhere:" for this computer. */
      key: string;
      text: "elsewhere";
      /** The machine whose terminals it heads; null for this computer. */
      machine: string | null;
    }
  | {
      kind: "new-terminal";
      key: "new:terminal";
      text: string;
    }
  | {
      kind: "new-space";
      key: string;
      text: string;
      /** The machine to start it on, or null for this computer. */
      machine: string | null;
    };

/**
 * The hub's rows for `world`, in the app's layout order:
 * 1. Every machine of `buildTree`'s tree, this computer first and then the
 *    others by name, even one with no rows under it: its header, then each
 *    of its spaces as a header followed by its tab dividers and terminal
 *    rows, then, when it has terminals no space holds, its elsewhere label
 *    followed by those.
 *    - Spaces: `spaces()` order, except that a linked checkout's space
 *      follows its repo's main checkout's, marked (`spaceOrder` of
 *      `world.checkouts`); a space with an entry there, a checkout or null
 *      for no repo, gets its checkout line.
 *    - Rows: every live terminal, where `buildTree` places it: in the space
 *      `spaceMembership` gives (its own pane or `herdr.space` label, else its
 *      nearest ancestor's), else under its machine's elsewhere label.
 *    - A space lists each of its tabs in order, empty ones included, as a
 *      divider followed by the tab's terminals in `panes()` order, then,
 *      without a divider, its terminals in none of its tabs; an elsewhere
 *      label lists its terminals in `terminals()` order. Each terminal's
 *      sub-terminals follow it, one level deeper (`walkTree`), then the
 *      finished terminals it started, oldest first, as `finished` rows at
 *      that depth. A terminal
 *      without a pane after its space's tabs, or under an elsewhere label,
 *      notes "no pane". The terminal and finished rows of a folded tab
 *      (`tabFolded`) are marked `folded`.
 *    - A row's status is `rowStatus`'s, so an agent nested under an agent
 *      shows done as idle.
 *    - Plain labels repeated within a space, or within one elsewhere, get
 *      ordinals (`  #1`, `#2`), in row order.
 * 2. The new-terminal row, named after the active space.
 * 3. The new-space row for this computer, and one per connected machine, by
 *    name.
 */
export function findRows(world: FindWorld): FindRow[] {
  const tree = buildTree(world);
  const machineSections = tree.machines.map((machine) => ({
    machine,
    sections: treeSections(machine, world.checkouts),
  }));
  const sections = machineSections.flatMap((m) => m.sections);

  // Each live terminal's model, with its ordinal, and its section's key.
  const models = new Map<string, TerminalRowModel>();
  const sectionOf = new Map<string, string>();
  for (const { key, groups } of sections) {
    const listings = groups.flatMap((g) =>
      g.listings.flatMap((l) => (l.kind === "terminal" ? [l] : [])),
    );
    // A plain terminal running a command shows it on its third line, with no
    // run time: the hub keeps no record of when commands started.
    const modelsHere = listings.map(({ step, status }) => {
      const command = runningCommand(step.node.terminal);
      return terminalRowModel(
        {
          ...step.node,
          status,
        },
        world.home,
        command && {
          text: command.text,
          since: null,
        },
      );
    });

    // A label two plain terminals share gets an ordinal on each, in order.
    const uses = new Map<string, number>();
    for (const m of modelsHere) {
      if (m.status === null) uses.set(m.label, (uses.get(m.label) ?? 0) + 1);
    }
    const seen = new Map<string, number>();
    for (const m of modelsHere) {
      const isShared = m.status === null && (uses.get(m.label) ?? 0) > 1;
      const ordinal = (seen.get(m.label) ?? 0) + 1;
      if (isShared) seen.set(m.label, ordinal);
      models.set(
        m.address,
        isShared
          ? {
              ...m,
              label: `${m.label}  #${ordinal}`,
              title: m.title ? `${m.title}  #${ordinal}` : `#${ordinal}`,
            }
          : m,
      );
      sectionOf.set(m.address, key);
    }
  }

  // The label of a top-level row's parent: a live terminal listed in
  // another section, or an agent that ended. A missing parent, an ended
  // plain one, and one in its own section (a parent cycle) give none.
  const byAddress = new Map(world.terminals.map((t) => [t.address, t]));
  const infoByAddress = new Map(world.agents.map((a) => [a.address, a]));
  const topParentLabel = (t: TerminalEntry): string | null => {
    const address = parentAddress(t);
    if (!address) return null;
    const listed = models.get(address);
    if (listed)
      return sectionOf.get(address) !== sectionOf.get(t.address)
        ? listed.label
        : null;
    const parent = byAddress.get(address);
    const isEndedAgent =
      parent !== undefined &&
      typeof parent.status === "string" &&
      parent.status !== "";
    return isEndedAgent
      ? agentLabel({
          terminal: parent,
          info: infoByAddress.get(address) ?? null,
          pane: null,
        })
      : null;
  };

  // Each tab by id, and each pane's position in its tab from 1, mod panes
  // counted, for the terminal rows' `tabIndex` and `paneIndex`.
  const tabById = new Map(
    world.spaces.flatMap((s) => s.tabs.map((tab) => [tab.id, tab] as const)),
  );
  const paneIndexOf = new Map<PaneInfo, number>();
  const panesSeen = new Map<string, number>();
  for (const p of world.panes) {
    const index = (panesSeen.get(p.tab) ?? 0) + 1;
    panesSeen.set(p.tab, index);
    paneIndexOf.set(p, index);
  }

  // A section's header, tab dividers and terminal rows.
  const sectionRows = ({
    key,
    space,
    machine,
    tree,
    groups,
  }: Section): FindRow[] => {
    const checkouts = world.checkouts;
    const checkoutLine =
      space && checkouts && space.id in checkouts
        ? checkoutText(space, checkouts[space.id], world.home)
        : null;
    const headed: FindRow[] = [
      space
        ? {
            kind: "space",
            key,
            text: [space.name, space.machine, checkoutLine]
              .filter(Boolean)
              .join("  "),
            space,
            checkoutLine,
            tree,
          }
        : {
            kind: "elsewhere",
            key,
            text: "elsewhere",
            machine,
          },
    ];
    for (const { tab, folded, listings } of groups) {
      if (tab && space)
        headed.push({
          kind: "tab",
          key: `t:${tab.id}`,
          text: tab.name,
          tab,
          space,
        });
      for (const listing of listings)
        headed.push(
          listing.kind === "terminal"
            ? terminalFindRow(listing, space, folded)
            : finishedFindRow(listing.step, space, folded),
        );
    }
    return headed;
  };

  // A listing's terminal row, listed under `space` (null under an
  // elsewhere label) and in a folded tab when `folded`.
  const terminalFindRow = (
    { step, parent, status, note }: TerminalListing,
    space: SpaceInfo | null,
    folded: boolean,
  ): FindRow => {
    const { node, depth } = step;
    const t = node.terminal;
    const model = models.get(t.address) as TerminalRowModel;
    return {
      kind: "terminal",
      key: `a:${t.address}`,
      text: [
        model.programName,
        model.title,
        model.status,
        model.detail?.kind === "blocked" ? model.detail.text : null,
        model.folder,
        space?.name ?? "elsewhere",
        node.machine,
      ]
        .filter(Boolean)
        .join("  "),
      address: t.address,
      model,
      since:
        status !== null &&
        status !== "working" &&
        typeof t.status_ms === "number"
          ? t.status_ms
          : null,
      depth,
      parentLabel: parent
        ? (models.get(parent.terminal.address) as TerminalRowModel).label
        : topParentLabel(t),
      note,
      space,
      machine: node.machine,
      tab: node.pane?.tab ?? null,
      tabIndex: node.pane ? (tabById.get(node.pane.tab)?.index ?? null) : null,
      paneIndex: node.pane ? (paneIndexOf.get(node.pane) ?? null) : null,
      folder: folderOf(t, world.home),
      folded,
    };
  };

  // A finished step's row, listed under `space` (null under an elsewhere
  // label) and in a folded tab when `folded`.
  const finishedFindRow = (
    { finished, parent, depth }: TreeFinishedStep,
    space: SpaceInfo | null,
    folded: boolean,
  ): FindRow => {
    const machine = machineOf(finished.address);
    return {
      kind: "finished",
      key: `f:${finished.address}`,
      text: [
        finishedLabel(finished),
        finishedOutcome(finished).text,
        "finished",
        space?.name ?? "elsewhere",
        machine,
      ]
        .filter(Boolean)
        .join("  "),
      finished,
      parent: parent.terminal.address,
      parentLabel: (models.get(parent.terminal.address) as TerminalRowModel)
        .label,
      parentTab: parent.pane?.tab ?? null,
      depth,
      space,
      machine,
      folded,
    };
  };

  const rows: FindRow[] = [];
  for (const { machine, sections: listed } of machineSections) {
    rows.push({
      kind: "machine",
      key: `m:${machine.name ?? ""}`,
      text: machine.name ?? "this computer",
      machine: {
        name: machine.name,
        state: machine.state,
        sinceMs: machine.sinceMs,
      },
    });
    for (const section of listed) rows.push(...sectionRows(section));
  }

  const active = world.spaces.find((s) => s.active);
  rows.push(
    {
      kind: "new-terminal",
      key: "new:terminal",
      text: active ? `new terminal in ${active.name}` : "new terminal",
    },
    {
      kind: "new-space",
      key: "new:space:",
      text: "new space",
      machine: null,
    },
    ...tree.machines.flatMap((m): FindRow[] =>
      m.name !== null && m.state === "connected"
        ? [
            {
              kind: "new-space",
              key: `new:space:${m.name}`,
              text: `new space on ${m.name}`,
              machine: m.name,
            },
          ]
        : [],
    ),
  );
  return rows;
}

/**
 * The terminal rows one header heads: a space's, or a machine's elsewhere
 * label's when `space` is null.
 */
interface Section {
  /** The header row's key: `s:<id>` or `elsewhere:<machine>`. */
  key: string;
  space: SpaceInfo | null;
  /** The machine it is under; null for this computer. */
  machine: string | null;
  /** A space's `spaceOrder` branch mark; null for an elsewhere label. */
  tree: "├─" | "└─" | null;
  /**
   * A space's tabs in order, then its loose terminals; an elsewhere
   * label's terminals alone.
   */
  groups: ListingGroup[];
}

/** The terminal rows of one tab, or a header's terminals in no tab. */
interface ListingGroup {
  /** The tab whose divider heads them; null for terminals in no tab. */
  tab: TabInfo | null;
  /** `tabFolded` of the tab; false without one. */
  folded: boolean;
  listings: Listing[];
}

/**
 * One row of a `Section` under a header or tab: a live terminal's or a
 * finished one's.
 */
type Listing = TerminalListing | FinishedListing;

/** One terminal row of a `Section`, before its label is settled. */
interface TerminalListing {
  kind: "terminal";
  /** Its `walkTree` step, with its depth. */
  step: TreeTerminalStep;
  /** The terminal it is nested under; null at the top level. */
  parent: TreeTerminal | null;
  /** `rowStatus` of it under `parent`. */
  status: AgentStatus | null;
  /**
   * "no pane" for a terminal without a pane in none of its space's tabs, or
   * under an elsewhere label; else null.
   */
  note: string | null;
}

/** One finished terminal's row of a `Section`. */
interface FinishedListing {
  kind: "finished";
  /** Its `walkTree` step, with its depth and parent. */
  step: TreeFinishedStep;
}

/**
 * `machine`'s live terminals as `buildTree` arranges them, one `Section`
 * per space in `spaceOrder`'s order by `checkouts` (a space without an
 * entry counts as in no repo), then its elsewhere's when it has terminals.
 */
function treeSections(
  machine: TreeMachine,
  checkouts: Record<string, SpaceCheckout | null> | null,
): Section[] {
  const ordered = spaceOrder(
    machine.spaces,
    (treeSpace) => checkouts?.[treeSpace.space.id] ?? null,
  );
  const sections = ordered.map(
    ({ space: treeSpace, tree }): Section => ({
      key: `s:${treeSpace.space.id}`,
      space: treeSpace.space,
      machine: machine.name,
      tree,
      groups: [
        ...treeSpace.tabs.map(
          (treeTab): ListingGroup => ({
            tab: treeTab.tab,
            folded: tabFolded(treeTab),
            listings: treeListings(treeTab.terminals, false),
          }),
        ),
        {
          tab: null,
          folded: false,
          listings: treeListings(treeSpace.loose, true),
        },
      ],
    }),
  );
  if (machine.elsewhere.length > 0)
    sections.push({
      key: `elsewhere:${machine.name ?? ""}`,
      space: null,
      machine: machine.name,
      tree: null,
      groups: [
        {
          tab: null,
          folded: false,
          listings: treeListings(machine.elsewhere, true),
        },
      ],
    });
  return sections;
}

/**
 * The rows of the top-level terminals `nodes`, every live terminal nested
 * under them and the finished terminals under those, in `walkTree` order;
 * `marksPaneless` notes "no pane" on each live one without a pane.
 */
function treeListings(
  nodes: TreeTerminal[],
  marksPaneless: boolean,
): Listing[] {
  // The terminal last walked at each depth: a row's parent is the one a
  // level up.
  const ancestors: TreeTerminal[] = [];
  return [...walkTree(nodes)].map((step): Listing => {
    if (step.kind === "finished")
      return {
        kind: "finished",
        step,
      };
    ancestors[step.depth] = step.node;
    const parent = step.depth > 0 ? ancestors[step.depth - 1] : null;
    return {
      kind: "terminal",
      step,
      parent,
      status: rowStatus(step.node, parent),
      note: marksPaneless && step.node.pane === null ? "no pane" : null,
    };
  });
}

/**
 * Whether the cursor can rest on `row`: every row but the machine headers,
 * tab dividers and elsewhere labels, which only label the rows under them.
 */
export function isSelectable(row: FindRow): boolean {
  return (
    row.kind !== "machine" && row.kind !== "tab" && row.kind !== "elsewhere"
  );
}

/**
 * The rows a query matches: `rows` without the machine headers, tab
 * dividers and elsewhere labels, folded terminal rows included.
 */
export function filterableRows(rows: readonly FindRow[]): FindRow[] {
  return rows.filter(isSelectable);
}

/**
 * The rows the hub lists while the query is empty: `rows` without the
 * terminal and finished rows of folded tabs, whose dividers stay.
 */
export function unfoldedRows(rows: readonly FindRow[]): FindRow[] {
  return rows.filter(
    (r) => (r.kind !== "terminal" && r.kind !== "finished") || !r.folded,
  );
}

/**
 * The rows the needs-you filter keeps, in `rows` order: `rows`' terminal
 * rows whose shown status (`TerminalRowModel.status`) is blocked or done,
 * and its finished rows that failed (`finishedOutcome`); one that exited 0
 * needs no one. Pass the `findRows` result, so they list in the tree's
 * order; the hub shows them as a flat list, or matches a query over them
 * alone.
 */
export function needsYouRows(rows: readonly FindRow[]): FindRow[] {
  return rows.filter(
    (r) =>
      (r.kind === "terminal" &&
        (r.model.status === "blocked" || r.model.status === "done")) ||
      (r.kind === "finished" && finishedOutcome(r.finished).failed),
  );
}
