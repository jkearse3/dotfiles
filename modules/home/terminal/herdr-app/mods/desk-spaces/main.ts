// Spaces with their agents under them, the `desk` layout's sidebar list:
// - The spaces: a stable color tick each, Git worktrees and jj workspaces under
//   their repo's main checkout, grouped by machine when more than one is
//   known. Under each space's name, the checkout its first terminal is in
//   ("dotfiles / ws3"), then, only where unusual, its branch and
//   ahead/behind (a jj checkout shows what the terminal prompt shows). Every
//   agent of a space has a row beneath it, one agent or many (sub-agents
//   under their agent), saying what it is (`agentName`) and, on a dim line,
//   where it is and what it is doing now or how far along it is. The chevron
//   on the space's name line folds them; folded, it shows the count in the
//   most urgent status's color. A space whose agents are all quiet (none
//   working or blocked) gets a "conflict" badge on its checkout line for a
//   jj conflict, else "review" for unshipped work.
// - "Needs you", a tray of fixed height at the bottom, so the spaces above
//   never move when it changes: every blocked agent, then every agent that
//   finished while you weren't looking (`done`, which the app turns `idle`
//   once you look), newest first. Click one to focus it.
// - The narrow rail shows each space's most urgent agent status and the `»`
//   that widens the sidebar again (`desk-chrome` relies on it).
// The agent next/previous keys walk "Needs you" first, then the tree.
// Click to switch, right-click for its menu, drag a space to reorder.
//
// Started as a copy of the app's shipped `spaces` mod plus the agent rows of
// its shipped `agents` mod (herdr-app 0.1.11).
//
// This file holds the view and its state; `checkouts.ts` looks up each
// space's Git or jj checkout, `agents.ts` gathers agents and tracks their
// status changes, and `rows.ts` draws the rows.
//
// `paths.ts` (imported by `checkouts.ts` and `rows.ts`) and `names.ts`
// (imported by `agents.ts`) beside these files are links to the shared copies
// in `mod-lib/`.

import { View, div, svg } from "gpui-kit";
import type {
  AsyncContext,
  Context,
  Element,
  MouseButtonEvent,
} from "gpui-kit";
import type { Props } from "gpui-shell";
import { v_flex, h_flex } from "gpui-base";
import {
  agents,
  focused,
  setAgentOrder,
  spaces,
  machines,
  panes,
  run,
  openOverlay,
  hc,
  theme,
  shared,
  setShared,
  window,
  layout,
} from "herdr";
import type { SpaceInfo, Status } from "herdr";
import { Checkouts, where } from "./checkouts.js";
import type { GitCheckout } from "./checkouts.js";
import {
  AgentHistory,
  RANK,
  gatherAgents,
  needsYou,
  topStatus,
} from "./agents.js";
import type { AgentStatus, CrewMember } from "./agents.js";
import {
  ROW_GAP,
  ROW_X,
  TEXT_X,
  TICK_X,
  agentRow,
  assignSpaceColors,
  avatarFill,
  checkoutBadge,
  checkoutLine,
  compact,
  focusBar,
  gitTail,
  hoverFill,
  jjTail,
  needsYouRows,
  subRow,
} from "./rows.js";
import type { SpaceRow, ThemeColors } from "./rows.js";

// The fields of a `layout()` block this mod reads. The app's typings type
// `layout()` as `unknown`.
interface LayoutNode {
  id?: string;
  size?: { px?: number };
  children?: LayoutNode[];
}

// A machine as `hc machine ls --json` lists it, the fields this mod reads.
interface MachineEntry {
  name: string;
  state: string;
  temporary?: boolean;
}

// The fields of `hc machine ls --json` this mod reads.
interface MachineList {
  machines?: MachineEntry[];
}

function find(node: LayoutNode | null, id: string): LayoutNode | null {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The sidebar's rail goes by its width, not a flag: dragging its edge narrows
// it too.
const narrow = () =>
  (find(layout() as LayoutNode, "sidebar")?.size?.px ?? Infinity) < 160;

// Makes a space on `machine`, or on this computer when it is null. Here the
// folder picker (`space-new`) asks for its folder first; it lists only this
// computer's folders, so a space on another machine is made without one.
const newSpace = (machine: string | null) =>
  machine
    ? run("space.new", { machine })
    : run("mod.open", { name: "space-new" });

// `toggleSidebar` is copied from the shipped `agents` mod.

// To the rail (on macOS wide enough for the traffic lights), or back to the
// width it had.
function toggleSidebar() {
  const width = find(layout() as LayoutNode, "sidebar")?.size?.px;
  if (!narrow()) setShared("sidebar.width", width);
  // Mods edited before the rail went by width still read the flag.
  setShared("sidebar.collapsed", !narrow());
  run("layout.resize", {
    id: "sidebar",
    px: narrow()
      ? (shared("sidebar.width") ?? 268)
      : window()?.platform === "macos"
        ? 76
        : 44,
  });
}

export default class SpacesAndAgents extends View {
  declare folded: Set<string | null>;
  declare checkouts: Checkouts;
  declare shown: Set<string>;
  // Space id -> when the space was first seen while this runs (ms).
  declare born: Record<string, number>;
  // The index in `spaces()` of the space row a drag started on, and of the
  // row it is over (null: no drag, or over a row it can't drop on).
  declare pressed: number | null;
  declare over: number | null;
  declare machines: MachineEntry[];
  declare foldedSpaces: Record<string, string | null>;
  declare history: AgentHistory;
  declare crews: Map<string, CrewMember[]>;
  declare listed: Map<string, Status>;

  init(_props: Props | undefined, cx: AsyncContext): void {
    // Machines whose spaces are folded away under their header.
    this.folded = new Set(
      JSON.parse(localStorage.getItem("machines.folded") ?? "[]") as (
        | string
        | null
      )[],
    );
    // Each space's checkout, looked up while this runs (see `Checkouts`).
    this.checkouts = new Checkouts(this.folded);
    // Spaces made while this runs wait (at most a moment) for their git, so a
    // worktree appears under its repo instead of jumping there.
    this.shown = new Set(spaces().map((s) => s.id));
    this.born = {};
    this.pressed = null;
    this.over = null;
    this.machines = [];
    // Space id -> its machine (null: this computer), for spaces whose agent
    // rows are folded away.
    this.foldedSpaces = JSON.parse(
      localStorage.getItem("spaces.folded") ?? "{}",
    ) as Record<string, string | null>;
    // Each agent's last status change (kept across restarts) and the focused
    // agent's held next/previous rank.
    this.history = new AgentHistory();
    // Space id -> its agents as listed this render (see `gatherAgents`).
    this.crews = new Map();
    this.listed = new Map(); // agent address -> its status this render
    // Agent durations count in minutes.
    cx.timer.every(30000, (cx) => cx.notify());
    this.refreshMachines(cx);
    cx.timer.every(15000, (cx) => this.refreshMachines(cx));
    // `git status` walks the whole tree, on another machine a process there:
    // only when its answer could have changed (see `Checkouts.due`).
    cx.timer.every(250, (cx) => this.checkNew(cx));
  }

  checkNew(cx: AsyncContext): void {
    const now = Date.now();
    const sp = spaces();
    for (const s of sp) if (!this.shown.has(s.id)) this.born[s.id] ??= now;
    const due = this.checkouts.due(now, sp, panes());
    if (due.size) this.checkouts.refreshGit(due, cx);
    if (sp.some((s) => !this.shown.has(s.id))) cx.notify();
  }

  refreshMachines(cx: AsyncContext): void {
    cx.spawn(async (cx) => {
      try {
        const r = await hc(["machine", "ls", "--json"]);
        if (r.code === 0)
          this.machines = (
            (JSON.parse(r.stdout) as MachineList).machines ?? []
          ).filter((m) => !m.temporary);
      } catch {}
      cx.notify();
    });
  }

  menu(w: SpaceInfo): void {
    // A popup is as tall as its items; height is only the most.
    openOverlay({
      mod: "menu",
      kind: "popup",
      width: 200,
      height: 260,
      props: { tab: "space", target: { id: w.id } },
    });
  }

  // Spaces in order, each worktree space moved under its main checkout's.
  ordered(): SpaceRow[] {
    const sp = spaces(),
      ps = panes();
    const ready = (w: SpaceInfo) =>
      this.shown.has(w.id) ||
      where(w, ps) in this.checkouts.git ||
      Date.now() - (this.born[w.id] ??= Date.now()) > 1500;
    for (const w of sp)
      if (!this.shown.has(w.id) && ready(w)) this.shown.add(w.id);
    const list = sp
      .map((w, i) => ({ w, i, g: this.checkouts.git[where(w, ps)] ?? null }))
      .filter((r) => this.shown.has(r.w.id));
    const mains = new Set(
      list.filter((r) => r.g && !r.g.linked).map((r) => r.g.repo),
    );
    const nested = (r: Omit<SpaceRow, "tree">) =>
      r.g?.linked && mains.has(r.g.repo);
    const out: SpaceRow[] = [];
    const placed = new Set(); // repos whose worktrees are listed (under the first of its spaces)
    for (const r of list) {
      if (nested(r)) continue;
      out.push({ ...r, tree: null });
      if (!r.g || r.g.linked || placed.has(r.g.repo)) continue;
      placed.add(r.g.repo);
      const kids = list.filter((k) => nested(k) && k.g.repo === r.g.repo);
      kids.forEach((k, n) =>
        out.push({ ...k, tree: n === kids.length - 1 ? "└─" : "├─" }),
      );
    }
    return out;
  }

  // The rows, under a header per machine once one isn't this computer.
  // Each space row comes with its agent rows (none on the rail).
  grouped(
    t: ThemeColors,
    collapsed: boolean,
    rows: SpaceRow[],
    now: number,
  ): Element[] {
    // Each space with its agent rows is one group. A hairline above each
    // space that isn't a worktree sets it apart from the one before; a
    // worktree stays under its repo's. Every group keeps 4px below its last
    // row, so a focused row's fill clears the next hairline. The active
    // space's color tick grows into a rail down its whole group: the space
    // you are in, apart from the accent bar on the one row holding focus.
    const draw = (r: SpaceRow) => {
      if (collapsed) return [compact(r, t, this.spaceStatus(r.w))];
      const rows = [this.row(r, t), ...this.agentRows(r, t, now)];
      // A space's color in the gutter left of its rows: a tick beside its
      // name, or, for the active space, the rail. A worktree has its branch
      // mark instead of a tick.
      const mark = div()
        .absolute()
        .left(TICK_X)
        .top(r.tree ? 6 : 11)
        .w(3)
        .rounded(2)
        .bg(avatarFill(r.w.id, t));
      return [
        v_flex()
          .id(`space-group-${r.w.id}`)
          .relative()
          .flex_none()
          .pl(ROW_X)
          .pb(4)
          .gap(ROW_GAP)
          .when(!r.tree, (el) => el.pt(4).border_t(1).border_color(t.border))
          .children(rows)
          .when(r.w.active, (el) => el.child(mark.bottom(10)))
          .when(!r.w.active && !r.tree, (el) => el.child(mark.h(16))),
      ];
    };
    const groups = this.machineGroups(rows);
    const loading = (m: string | null) => {
      const layout = machines().find((k) => k.name === m)?.layout;
      return (
        layout === "loading" ||
        (!layout &&
          this.machines.some((k) => k.name === m && k.state === "connected")) ||
        spaces().some((s) => (s.machine ?? null) === m && !this.shown.has(s.id))
      );
    };
    const loadingRow = (m: string | null) =>
      div()
        .id(`machine-loading-${m ?? "local"}`)
        .h(28)
        .flex_none()
        .px(8)
        .text_size(12)
        .text_color(t.dim)
        .child(collapsed ? "…" : "Loading…");
    if (groups.length === 1)
      return loading(null) && !rows.length
        ? [loadingRow(null)]
        : rows.flatMap(draw);
    return groups.flatMap(([m, mine]) => {
      const machine = this.machines.find((k) => k.name === m);
      const connected = !m || machine?.state === "connected";
      const folded = this.folded.has(m);
      const head = h_flex()
        .id(`machine-${m ?? "local"}`)
        .h(26)
        .flex_none()
        .px(collapsed ? 2 : 8)
        .gap(7)
        .items_center()
        .text_size(11)
        .text_color(t.dim)
        .cursor_pointer()
        .hover((s) => s.bg(hoverFill(t)))
        .on_click((_e, cx) => {
          folded ? this.folded.delete(m) : this.folded.add(m);
          localStorage.setItem(
            "machines.folded",
            JSON.stringify([...this.folded]),
          );
          cx.notify();
        })
        .child(
          svg(`mods/workspace-chrome/${m ? "server" : "monitor"}.svg`)
            .size(13)
            .flex_none(),
        )
        .when(!collapsed, (el) =>
          el
            .child(
              div()
                .flex_1()
                .truncate()
                .child(m ?? "This computer"),
            )
            .when(!connected, (el) =>
              el.child(
                div()
                  .flex_none()
                  .child((machine?.state ?? "asleep").replace(/_/g, " ")),
              ),
            )
            .when(connected, (el) =>
              el.child(
                div()
                  .id(`machine-add-${m ?? "local"}`)
                  .flex_none()
                  .px(4)
                  .rounded(4)
                  .hover((s) => s.bg(t.hover).text_color(t.foreground))
                  .on_click((_e, cx) => {
                    cx.stop_propagation();
                    newSpace(m);
                  })
                  .child("+"),
              ),
            )
            .child(
              div()
                .size(6)
                .rounded(3)
                .flex_none()
                .bg(connected ? t.ansi2 : t.dim),
            )
            .child(
              svg(
                `mods/workspace-chrome/chevron-${folded ? "right" : "down"}.svg`,
              )
                .size(11)
                .flex_none(),
            ),
        );
      const empty = h_flex()
        .id(`machine-new-${m ?? "local"}`)
        .h(28)
        .flex_none()
        .px(8)
        .gap(7)
        .items_center()
        .rounded(7)
        .text_size(12)
        .text_color(t.dim)
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_click(() => newSpace(m))
        .child(svg("mods/workspace-chrome/plus.svg").size(12))
        .when(!collapsed, (el) => el.child("New space there"));
      return [
        head,
        ...(folded
          ? []
          : mine.length
            ? mine.flatMap(draw)
            : [loading(m) ? loadingRow(m) : empty]),
      ];
    });
  }

  // `rows` by machine, in the order `grouped` draws them: [machine, its rows]
  // pairs, this computer (null) first, then every other machine by name, each
  // one with spaces in `rows` or listed by `hc machine ls` (`this.machines`),
  // so a pair's rows may be empty. Without other machines, the one pair holds
  // every row. Each machine's rows keep their order in `rows`.
  machineGroups(rows: SpaceRow[]): [string | null, SpaceRow[]][] {
    const remote = [
      ...new Set([
        ...rows.map((r) => r.w.machine).filter(Boolean),
        ...this.machines.map((m) => m.name),
      ]),
    ].sort();
    if (!remote.length) return [[null, rows]];
    return [null, ...remote].map((m) => [
      m,
      rows.filter((r) => (r.w.machine ?? null) === m),
    ]);
  }

  row({ w, i, g, tree }: SpaceRow, t: ThemeColors): Element {
    // The active space says so by its name, bold and bright, and by its rail
    // (`grouped`). Its row holds the focus mark when no agent row of it does:
    // a shell has focus, or its agent rows are folded away.
    const on = w.active;
    const holdsFocus = on && !this.agentRowFocused(w);
    const checkout = checkoutLine(w, g, t);
    const badge = checkoutBadge(this.crew(w), g, t);
    const quietRepo = Boolean(tree) || Boolean(checkout);
    const tail = g
      ? g.jj
        ? jjTail(g, quietRepo, w.name, t)
        : gitTail(g as GitCheckout, quietRepo, w.name, t)
      : null;
    const foldToggle = this.foldToggle(w, t);
    // The row is as tall as its lines of text (the name, then the checkout
    // line and the repo status when shown, set close together) with even
    // padding, a worktree's a little tighter; a worktree's branch mark lines
    // up with its name. The color tick or rail is the group's (`grouped`).
    return v_flex()
      .relative()
      .id(`space-${w.id}`)
      .pl(tree ? 0 : TEXT_X - ROW_X)
      .pr(8)
      .py(tree ? 5 : 6)
      .flex_none()
      .justify_center()
      .rounded(6)
      .hover((s) => s.bg(hoverFill(t)))
      .when(holdsFocus, (el) => el.bg(t.hover).child(focusBar(t)))
      .when(this.pressed === i && this.over !== i, (el) => el.opacity(0.5))
      .when(
        this.pressed !== null && this.over === i && this.pressed !== i,
        (el) =>
          el.child(
            div()
              .absolute()
              .left(0)
              .right(0)
              .h(2)
              .bg(t.accent)
              .when(this.pressed < i, (line) => line.bottom(0))
              .when(this.pressed > i, (line) => line.top(0)),
          ),
      )
      .on_mouse_down("left", () => {
        this.pressed = i;
        this.over = i;
      })
      .on_mouse_move((_e, cx) => {
        const source = spaces()[this.pressed];
        const over =
          source && (source.machine ?? null) === (w.machine ?? null) ? i : null;
        if (this.pressed !== null && this.over !== over) {
          this.over = over;
          cx.notify();
        }
      })
      .on_mouse_up("left", (_e, cx) => {
        const from = this.pressed;
        const over = this.over;
        this.pressed = null;
        this.over = null;
        if (from !== null && over === i && from !== i)
          run("space.move", { id: spaces()[from].id, index: i + 1 });
        else if (from === i) run("space.select", { id: w.id });
        cx.notify();
      })
      .on_mouse_down("right", () => this.menu(w))
      .child(
        h_flex()
          .gap(9)
          .items_start()
          .when(Boolean(tree), (el) =>
            el
              .pl(16)
              .child(
                svg("mods/workspace-chrome/branch.svg")
                  .mt(2)
                  .size(13)
                  .flex_none()
                  .text_color(t.dim),
              ),
          )
          .child(
            v_flex()
              .flex_1()
              .min_w(0)
              .line_height(1.3)
              .child(
                h_flex()
                  .min_w(0)
                  .gap(6)
                  .items_center()
                  .child(
                    div()
                      .flex_1()
                      .min_w(0)
                      .truncate()
                      .text_color(on ? t.foreground : t.muted)
                      .when(on, (el) => el.font_semibold())
                      .child(w.name),
                  )
                  .when(Boolean(foldToggle), (el) => el.child(foldToggle)),
              )
              .when(Boolean(checkout) || Boolean(badge), (el) =>
                el.child(
                  h_flex()
                    .min_w(0)
                    .gap(6)
                    .items_center()
                    .child(
                      div()
                        .flex_1()
                        .min_w(0)
                        .when(Boolean(checkout), (el) => el.child(checkout)),
                    )
                    .when(Boolean(badge), (el) => el.child(badge)),
                ),
              )
              .when(Boolean(tail), (el) => el.child(tail)),
          ),
      );
  }

  crew(w: SpaceInfo): CrewMember[] {
    return this.crews.get(w.id) ?? [];
  }

  // The most urgent status among a space's agents, null without agents.
  spaceStatus(w: SpaceInfo): AgentStatus | null {
    return topStatus(this.crew(w).map((m) => m.status));
  }

  // Whether focus sits on one of the space's agent rows (an agent, or a
  // sub-agent shown in its place): never when its agent rows are folded away.
  agentRowFocused(w: SpaceInfo): boolean {
    if (w.id in this.foldedSpaces) return false;
    const shown = focused()?.agent;
    return this.crew(w).some(
      (m) => m.a.focused || m.subs.some((s) => s.t.address === shown),
    );
  }

  setSpaceFolded(w: SpaceInfo, folded: boolean): void {
    if (folded) this.foldedSpaces[w.id] = w.machine ?? null;
    else delete this.foldedSpaces[w.id];
    localStorage.setItem("spaces.folded", JSON.stringify(this.foldedSpaces));
  }

  // Forgets folds of spaces that are gone. Only on machines whose layout is
  // read: while one loads, its spaces aren't listed yet.
  pruneFoldedSpaces(sp: SpaceInfo[]): void {
    const ids = new Set(sp.map((s) => s.id));
    const ready = new Set(
      machines()
        .filter((m) => m.layout === "ready")
        .map((m) => m.name),
    );
    const gone = Object.entries(this.foldedSpaces).filter(
      ([id, machine]) => !ids.has(id) && ready.has(machine),
    );
    if (!gone.length) return;
    for (const [id] of gone) delete this.foldedSpaces[id];
    localStorage.setItem("spaces.folded", JSON.stringify(this.foldedSpaces));
  }

  // The end of the name line of a space with agents: a chevron that folds
  // their rows and, folded, adds how many agents in the most urgent one's
  // color. Pressing it neither selects nor drags the space.
  foldToggle(w: SpaceInfo, t: ThemeColors): Element | null {
    const crew = this.crew(w);
    if (!crew.length) return null;
    const keep = (_e: MouseButtonEvent, cx: Context) => cx.stop_propagation();
    const open = !(w.id in this.foldedSpaces);
    const top = this.spaceStatus(w);
    return h_flex()
      .id(`space-fold-${w.id}`)
      .flex_none()
      .h(18)
      .px(3)
      .gap(3)
      .items_center()
      .rounded(4)
      .text_size(11)
      .text_color(open ? t.dim : (t[top] ?? t.dim))
      .cursor_pointer()
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", keep)
      .on_click((_e, cx) => {
        cx.stop_propagation();
        this.setSpaceFolded(w, open);
        cx.notify();
      })
      .when(!open, (el) => el.child(String(crew.length)))
      .child(
        svg(`mods/workspace-chrome/chevron-${open ? "down" : "right"}.svg`)
          .size(11)
          .flex_none(),
      );
  }

  // The agent rows under an unfolded space, their icons under the start of
  // its name (past its color tick, or a worktree's branch mark).
  agentRows({ w, tree }: SpaceRow, t: ThemeColors, now: number): Element[] {
    if (w.id in this.foldedSpaces) return [];
    const indent = tree ? 52 : TEXT_X;
    const shown = focused()?.agent;
    return this.crew(w).flatMap((m) => [
      agentRow(m, indent, t, now, this.history.since(m.a)),
      ...m.subs.map((s) => subRow(t, s, shown, indent + 4, this.listed)),
    ]);
  }

  render(): Element {
    const t = theme() as ThemeColors;
    const collapsed = narrow();
    const sp = spaces();
    assignSpaceColors(sp);

    const now = Date.now();
    const list = agents();
    this.history.track(list, now);
    this.history.hold(list);
    this.pruneFoldedSpaces(sp);
    const { byAddress, crews, listed } = gatherAgents(list, sp);
    this.crews = crews;
    this.listed = listed;
    const tray = needsYou(list, (a) => RANK[a.status] ?? 0);

    // Next/previous agent: "Needs you", then the tree in the machine order
    // `grouped` draws, folded machines and spaces included. The focused agent
    // keeps its "Needs you" slot here after looking turns it from done to
    // idle (`orderRank`), so stepping on reaches the one after it, though the
    // tray itself drops it. An agent whose space isn't shown yet is left out
    // here; the app appends it.
    const rows = this.ordered();
    const treeOrder = this.machineGroups(rows).flatMap(([, mine]) =>
      mine.flatMap((r) => this.crew(r.w).map((m) => m.a.address)),
    );
    const trayOrder = needsYou(list, (a) => this.history.orderRank(a)).map(
      (a) => a.address,
    );
    setAgentOrder([...new Set([...trayOrder, ...treeOrder])]);

    return v_flex()
      .size_full()
      .min_h(0)
      .bg(t.chrome)
      .text_size(13)
      .child(
        h_flex()
          .h(31)
          .pl(16)
          .pr(10)
          .items_center()
          .justify_between()
          .text_size(11.5)
          .text_color(t.dim)
          .when(!collapsed, (el) =>
            el.child(div().text_size(10.5).font_semibold().child("SPACES")),
          )
          .child(
            div()
              .id("space-new")
              .size(26)
              .flex_none()
              .flex()
              .items_center()
              .justify_center()
              .rounded(6)
              .hover((s) => s.bg(t.hover).text_color(t.foreground))
              .on_click(() => newSpace(null))
              .child(svg("mods/workspace-chrome/plus.svg").size(14)),
          ),
      )
      .child(
        v_flex()
          .flex_1()
          .min_h(0)
          .px(8)
          .pb(14)
          .overflow_y_scrollbar()
          .mode("always")
          .on_mouse_up("left", (_e, cx) => {
            this.pressed = null;
            cx.notify();
          })
          .children(this.grouped(t, collapsed, rows, now)),
      )
      .when(!collapsed, (el) =>
        el.child(
          v_flex()
            .id("needs-you-tray")
            .flex_none()
            .px(8)
            .pt(4)
            .pb(8)
            .gap(ROW_GAP)
            .border_t(1)
            .border_color(t.border)
            .children(
              needsYouRows(tray, byAddress, t, now, (a) =>
                this.history.since(a),
              ),
            ),
        ),
      )
      .when(collapsed, (el) =>
        el.child(
          h_flex()
            .h(28)
            .flex_none()
            .items_center()
            .justify_center()
            .child(
              div()
                .id("collapse")
                .text_size(13)
                .text_color(t.dim)
                .hover((s) => s.text_color(t.foreground))
                .on_click(toggleSidebar)
                .child("»"),
            ),
        ),
      );
  }
}
