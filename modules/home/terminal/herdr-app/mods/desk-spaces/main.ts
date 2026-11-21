// Spaces with their agents under them, the `desk` layout's sidebar list:
// - The machines: a header for each (`machineHeader`), even when this
//   computer is the only one, naming this computer as its herdr-core does.
//   While `hc machine ls` reports a machine as other than connected, its
//   header shows that state and how long it has lasted ("needs login ·
//   14m"), and its spaces are dimmed. A header folds its machine's spaces
//   away; its "+" makes a space there.
// - The spaces under their machine, in the app's order (`spaces()`), each
//   one line: a stable color tick and its name. A space appears as soon as
//   the app lists it; a Git worktree's or jj workspace's space is a row like
//   any other, and the checkouts show on the terminal rows instead.
//   Beneath it, each of the space's tabs in order starts with a divider
//   (`tabDivider`: its name and a rule), empty tabs included, followed by a
//   row for every live terminal the shared tree (`buildTree`) places in that
//   tab, agents and plain shells alike, with the terminals each started
//   nested under it, a step further in per level (`DEPTH_INDENT`), even
//   when they show in another tab, the rows spaced a little wider apart
//   than the space rows (`TERMINAL_ROW_GAP`). Every row is `terminalRow`'s:
//   a 3px stripe down its left edge in the color of its state
//   (`stripeColor`: an agent's status color, cyan for a plain terminal
//   running a command, else grey), then its program and title, then on a
//   dim second line where it is now: in a Git or jj checkout, that checkout
//   ("dotfiles", "dotfiles / ws3"), the path below its root, dimmer
//   ("modules/home"), and after " · " its branch (unless main, master or
//   the checkout's folder name) and ahead/behind, or its jj bookmark and
//   distance as the terminal prompt shows them (`terminalCheckoutLine`);
//   in no checkout, or until its checkout is found, the folder itself.
//   That checkout line ends with a "conflict" badge when its jj checkout
//   has a conflict, whatever the terminal is doing, else, on an agent
//   neither working nor blocked, a "review" badge for unshipped work
//   (`terminalCheckoutBadge`). An agent's adds a third line with why it
//   is blocked, what it is doing now, or else its status word, and at its
//   end how long it has been in its status (while it works, "quiet 12m" in
//   amber once it has shown no new report message, turn or
//   state for 10 minutes). A plain terminal running a command other than
//   its shell (`make dev`) adds a third line with that command in cyan, in
//   the terminal's font, and how long it has run, once it has run 2 seconds
//   (`CommandStarts`), so quick commands do not make rows jump. Clicking a
//   row focuses its pane, or peeks at a terminal without one; the focused
//   terminal's row is filled, and any other one under the mouse fainter.
//   After a terminal's nested rows come the terminals it started that have
//   finished, oldest first (`finishedRow`: no stripe, a ✓, or a ✗ when it
//   failed, under the live rows' icons, its name, how it ended and when);
//   clicking one goes to the terminal that started it, and
//   right-clicking one offers a "Remove" chip at its end that removes it
//   with `hc rm` (any other press dismisses the chip). A settled
//   tab's divider is dimmed, and its rows stay hidden (`tabFolded`) until an
//   agent in it is blocked or done or a finished terminal in it failed;
//   there is no toggle. The space's terminals in
//   no tab of it follow its tabs, without a divider, marked "no pane". The
//   chevron on the space's name line folds all of that; folded, it shows how
//   many agents, at any depth, in the most urgent status's color (finished
//   terminals count for neither).
// - Last under each machine, its terminals no space holds
//   (`TreeMachine.elsewhere`, such as background terminals) under a small
//   "ELSEWHERE" heading, drawn and clicked like a space's terminal rows,
//   each without a pane marked "no pane", the section a little dimmed. It
//   has no fold of its own, and no space's rail status or fold count
//   includes it.
// - "Needs you", a tray of fixed height at the bottom, so the spaces above
//   never move when it changes: every blocked agent, then every agent that
//   finished while you weren't looking (`done`, which the app turns `idle`
//   once you look), newest first. Each row's second line names the agent's
//   space, then its machine as the machine headers name it ("~ · box"),
//   this computer included. Click one to focus it.
// - The narrow rail lists the spaces in the same order, each by its number
//   in `spaces()` and its most urgent agent status, and shows the `»`
//   that widens the sidebar again (`desk-chrome` relies on it).
// The agent next/previous keys walk "Needs you" first, then the tree.
// Click to switch, right-click for its menu, drag a space to reorder.
//
// Started as a copy of the app's shipped `spaces` mod plus the agent rows of
// its shipped `agents` mod (herdr-app 0.1.11).
//
// This file holds the view and its state, and shares each space's
// checkout (`publishCheckouts`); `checkouts.ts` looks up the Git or jj
// checkout of each space's folder and each live terminal's,
// `finished-loader.ts` reads the finished terminals, `agents.ts` picks the
// agents that need you and tracks their status and activity changes,
// `rows.ts` draws the rail
// entries, the terminal rows' checkout lines and the tray, and
// `tree-rows.ts` draws the machine headers, tab dividers and terminal rows.
//
// `agent-marks.ts`, `checkout-badge.ts`, `checkout-root.ts`, `finished.ts`,
// `foreground.ts`, `labels.ts`, `names.ts`, `paths.ts`, `program-icon.ts`,
// `quiet.ts`, `row-colors.ts`, `space-order.ts`, `status.ts`,
// `terminals.ts`, `tree-rows.ts` and `tree.ts` beside these files are links
// to the shared copies in `mod-lib/`.

import { View, div, svg } from "gpui-kit";
import type {
  AsyncContext,
  Color,
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
  terminals,
  run,
  openOverlay,
  hc,
  home,
  notify,
  settings,
  theme,
  shared,
  setShared,
  window,
  layout,
} from "herdr";
import type { AgentInfo, SpaceInfo, TabInfo } from "herdr";
import { Checkouts, terminalPlace } from "./checkouts.js";
import { AgentHistory, needsYou } from "./agents.js";
import { FinishedLoader } from "./finished-loader.js";
import { FINISHED_TERMINALS_KEY, finishedLabel } from "./finished.js";
import type { FinishedTerminal } from "./finished.js";
import { CommandStarts } from "./foreground.js";
import { agentLabel, blockedKind, terminalRowModel } from "./labels.js";
import { hoverFill } from "./row-colors.js";
import { SPACE_CHECKOUTS_KEY } from "./space-order.js";
import { RANK, topStatus } from "./status.js";
import type { AgentStatus } from "./status.js";
import type { TerminalEntry } from "./terminals.js";
import { buildTree, rowStatus, tabFolded, walkTree } from "./tree.js";
import type {
  MachineEntry,
  TreeMachine,
  TreeFinishedStep,
  TreeSpace,
  TreeTerminal,
  TreeTerminalStep,
} from "./tree.js";
import {
  finishedRow,
  machineHeader,
  tabDivider,
  terminalRow,
} from "./tree-rows.js";
import {
  ROW_GAP,
  ROW_X,
  DEPTH_INDENT,
  TERMINAL_ROW_GAP,
  TERMINAL_ROW_INSET,
  TERMINAL_ROW_PAD_X,
  TEXT_X,
  TICK_X,
  assignSpaceColors,
  avatarFill,
  compact,
  focusBar,
  needsYouRows,
  terminalCheckoutLine,
} from "./rows.js";
import type { SpaceRow, ThemeColors } from "./rows.js";

// The fields of a `layout()` block this mod reads. The app's typings type
// `layout()` as `unknown`.
interface LayoutNode {
  id?: string;
  size?: { px?: number };
  children?: LayoutNode[];
}

// The fields of `hc machine ls --json` this mod reads.
interface MachineList {
  machines?: MachineEntry[];
}

// The fields of `hc server status --json` this mod reads: the name of this
// computer's herdr-core.
interface ServerStatus {
  core?: { name?: string };
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
  // The JSON of the `SPACE_CHECKOUTS_KEY` value last written (see
  // `publishCheckouts`).
  declare publishedCheckouts: string;
  // The index in `spaces()` of the space row a drag started on, and of the
  // row it is over (null: no drag, or over a row it can't drop on).
  declare pressed: number | null;
  declare over: number | null;
  declare machines: MachineEntry[];
  // What `hc server status` names this computer; null until it answers.
  declare thisComputerName: string | null;
  declare foldedSpaces: Record<string, string | null>;
  declare history: AgentHistory;
  declare listings: Map<string, SpaceListing>;
  declare finished: FinishedLoader;
  // The JSON of the `FINISHED_TERMINALS_KEY` value last written (see
  // `publishFinished`).
  declare publishedFinished: string;
  // The JSON of the last `FINISHED_TERMINALS_KEY` value another view wrote
  // that this one read the finished terminals again for (see
  // `followFinished`); null before any.
  declare followedFinished: string | null;
  // The address of the finished terminal whose row shows the "Remove" chip
  // (`finishedRowElement`); null when no row does.
  declare removeChipAddress: string | null;
  // When each plain terminal's running command started, for its row's
  // third line.
  declare commands: CommandStarts;

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
    // What an earlier run left there (the value persists), so an unchanged
    // value is not written again.
    this.publishedCheckouts = JSON.stringify(
      shared(SPACE_CHECKOUTS_KEY) ?? null,
    );
    this.pressed = null;
    this.over = null;
    this.machines = [];
    this.thisComputerName = null;
    // Space id -> its machine (null: this computer), for spaces whose
    // terminal rows are folded away.
    this.foldedSpaces = JSON.parse(
      localStorage.getItem("spaces.folded") ?? "{}",
    ) as Record<string, string | null>;
    // Each agent's last status change and last activity (both kept across
    // restarts) and the focused agent's held next/previous rank.
    this.history = new AgentHistory();
    // Space id -> its tabs' and loose terminal rows this render (see
    // `spaceListing`).
    this.listings = new Map();
    // The finished terminals, read when the live ones change, on the
    // machines tick, after a removal, and when another view changes the
    // shared ones.
    this.finished = new FinishedLoader();
    // As with `publishedCheckouts`, what an earlier run left there.
    this.publishedFinished = JSON.stringify(
      shared(FINISHED_TERMINALS_KEY) ?? null,
    );
    this.followedFinished = null;
    this.removeChipAddress = null;
    // Kept across restarts; `checkNew` stamps new commands.
    this.commands = new CommandStarts();
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
    const entries = terminals() as unknown as TerminalEntry[];
    const live = entries.filter((k) => k.state === "live");
    const liveAddresses = live.map((k) => k.address);
    this.finished.checkLive(liveAddresses, cx);
    this.publishFinished(liveAddresses);
    this.followFinished(cx);
    const due = this.checkouts.due(now, sp, panes(), live);
    if (due.size) this.checkouts.refreshGit(due, cx);
    this.publishCheckouts(sp);
    // A command's row line appears once it has run long enough, and goes
    // when it ends.
    if (this.commands.track(entries, now)) cx.notify();
  }

  // Shares each space's checkout (`SPACE_CHECKOUTS_KEY`: space id ->
  // `SpaceCheckout`, null for a folder in no repo, a space not looked up yet
  // left out, a space that is gone dropped) for views that run no jj or git
  // of their own. `setShared` persists the value and re-renders every mod,
  // so it writes only when the value differs from the last one written;
  // running from `checkNew`'s timer rather than `render`, it picks up a
  // finished look or a removed space within a tick.
  publishCheckouts(sp: SpaceInfo[]): void {
    const value = this.checkouts.spaceCheckouts(sp);
    const json = JSON.stringify(value);
    if (json === this.publishedCheckouts) return;

    this.publishedCheckouts = json;
    setShared(SPACE_CHECKOUTS_KEY, value);
  }

  // Shares the finished terminals the tree nests, those whose parent is one
  // of the live terminals `liveAddresses` (`FINISHED_TERMINALS_KEY`: an
  // array of `FinishedTerminal`, in the loader's order), for views that run
  // no `hc` of their own. Like `publishCheckouts`, it writes only when the
  // value differs from the last one written, from `checkNew`'s timer.
  publishFinished(liveAddresses: string[]): void {
    const live = new Set(liveAddresses);
    const value = this.finished.finished.filter(
      (f) => f.parent !== null && live.has(f.parent),
    );
    const json = JSON.stringify(value);
    if (json === this.publishedFinished) return;

    this.publishedFinished = json;
    setShared(FINISHED_TERMINALS_KEY, value);
  }

  // Reads the finished terminals again when another view wrote
  // `FINISHED_TERMINALS_KEY` (the find hub drops a terminal it removed with
  // `hc rm`), so this sidebar's rows catch up at once rather than on the
  // machines tick; `publishFinished` then writes the result if its view
  // changed. It reads once per value written by another view
  // (`followedFinished`), and writes nothing itself, so it cannot loop: a
  // read that changes nothing leaves the other value standing and is not
  // repeated, and two writers each write only when their own view changes.
  // It runs after `publishFinished`, so a read that just finished is
  // written before the values are compared.
  followFinished(cx: AsyncContext): void {
    const json = JSON.stringify(shared(FINISHED_TERMINALS_KEY) ?? null);
    if (json === this.publishedFinished || json === this.followedFinished)
      return;

    this.followedFinished = json;
    this.finished.refresh(cx);
  }

  // Reads the other machines (`hc machine ls`) and, until it has it, this
  // computer's name (`hc server status`), then redraws. A failed read keeps
  // what the last one gave. It also reads the finished terminals again.
  refreshMachines(cx: AsyncContext): void {
    this.finished.refresh(cx);
    cx.spawn(async (cx) => {
      try {
        const r = await hc(["machine", "ls", "--json"]);
        if (r.code === 0)
          this.machines = (
            (JSON.parse(r.stdout) as MachineList).machines ?? []
          ).filter((m) => !m.temporary);
      } catch {}
      if (this.thisComputerName === null)
        try {
          const r = await hc(["server", "status", "--json"]);
          if (r.code === 0)
            this.thisComputerName =
              (JSON.parse(r.stdout) as ServerStatus).core?.name || null;
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

  // Every space, in the app's order (`spaces()`).
  ordered(): SpaceRow[] {
    return spaces().map((w, i) => ({ w, i }));
  }

  // The rows under a header per machine of `treeMachines` (`buildTree`), in
  // its order, even when this computer is the only one: each machine's space
  // rows from `rows` in their order, or, without any, a loading row or a
  // "New space there" row, then its Elsewhere section (`elsewhereSection`,
  // none on the rail); none of these while the machine is folded. Each space
  // row comes with its terminal rows (none on the rail). The spaces of a
  // machine `hc machine ls` reports as other than connected are dimmed.
  grouped(
    t: ThemeColors,
    collapsed: boolean,
    treeMachines: TreeMachine[],
    rows: SpaceRow[],
    now: number,
  ): Element[] {
    // Each space with its terminal rows is one group. A hairline above each
    // space sets it apart from the one before. Every group keeps 4px below
    // its last row, so a focused row's fill clears the next hairline. The
    // active space's color tick grows into a rail down its whole group: the
    // space you are in, apart from the fill on the one row holding focus.
    const draw = (r: SpaceRow) => {
      if (collapsed) return [compact(r, t, this.spaceStatus(r.w))];
      const rows = [this.row(r, t), ...this.terminalRows(r, t, now)];
      // A space's color in the gutter left of its rows: a tick beside its
      // name, or, for the active space, the rail.
      const mark = div()
        .absolute()
        .left(TICK_X)
        .top(11)
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
          .pt(4)
          .border_t(1)
          .border_color(t.border)
          .children(rows)
          .when(r.w.active, (el) => el.child(mark.bottom(10)))
          .when(!r.w.active, (el) => el.child(mark.h(16))),
      ];
    };
    const loading = (m: TreeMachine) => {
      const layout = machines().find((k) => k.name === m.name)?.layout;
      return layout === "loading" || (!layout && m.state === "connected");
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
    return treeMachines.flatMap((machine) => {
      const m = machine.name;
      const mine = rows.filter((r) => (r.w.machine ?? null) === m);
      const connected = m === null || machine.state === "connected";
      // `hc machine ls` reports it, in a state other than connected.
      const isAway = machine.state !== null && !connected;
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
        .hover((s) => s.bg(hoverFill(t, t.chrome)))
        .on_click((_e, cx) => {
          folded ? this.folded.delete(m) : this.folded.add(m);
          localStorage.setItem(
            "machines.folded",
            JSON.stringify([...this.folded]),
          );
          cx.notify();
        })
        .child(
          machineHeader(t, machine, now, {
            thisComputerName: this.thisComputerName,
            narrow: collapsed,
          }),
        )
        .when(!collapsed, (el) =>
          el
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
      const spaceRows = mine.length
        ? mine.flatMap(draw).map((el) => (isAway ? el.opacity(0.5) : el))
        : [loading(machine) ? loadingRow(m) : empty];
      if (folded) return [head];
      const elsewhere = collapsed
        ? null
        : this.elsewhereSection(machine, isAway, t, now);
      return [head, ...spaceRows, ...(elsewhere ? [elsewhere] : [])];
    });
  }

  row({ w, i }: SpaceRow, t: ThemeColors): Element {
    // The active space says so by its name, bold and bright, and by its rail
    // (`grouped`). Its row holds focus (filled, with the accent bar) when no
    // terminal row of it does: its rows are folded away, or focus is on no
    // terminal of it.
    const on = w.active;
    const holdsFocus = on && !this.terminalRowFocused(w);
    const foldToggle = this.foldToggle(w, t);
    // The row is one line, the name, with even padding. The color tick or
    // rail is the group's (`grouped`).
    return v_flex()
      .relative()
      .id(`space-${w.id}`)
      .pl(TEXT_X - ROW_X)
      .pr(8)
      .py(6)
      .flex_none()
      .justify_center()
      .rounded(6)
      .hover((s) => s.bg(hoverFill(t, t.chrome)))
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
              // The `when` above shows this line only while `pressed` is set.
              .when(this.pressed! < i, (line) => line.bottom(0))
              .when(this.pressed! > i, (line) => line.top(0)),
          ),
      )
      .on_mouse_down("left", () => {
        this.pressed = i;
        this.over = i;
      })
      .on_mouse_move((_e, cx) => {
        // A null `pressed` (no drag) indexes as "null": no space.
        const source = spaces()[this.pressed as number];
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
          .min_w(0)
          .gap(6)
          .items_center()
          .line_height(1.3)
          .child(
            div()
              .flex_1()
              .min_w(0)
              .truncate()
              .text_color(on ? t.foreground : t.muted)
              .when(on, (el) => el.font_semibold())
              .child(w.name),
          )
          // `when` runs this only for a space with a fold toggle.
          .when(Boolean(foldToggle), (el) => el.child(foldToggle!)),
      );
  }

  // The space's live terminal rows this render, in the order they are
  // drawn: each tab's, then the loose ones. Finished rows are left out.
  listing(w: SpaceInfo): TerminalListing[] {
    const listing = this.listings.get(w.id);
    if (!listing) return [];
    return terminalRowsOf([
      ...listing.tabs.flatMap((tab) => tab.rows),
      ...listing.loose,
    ]);
  }

  // The statuses the space's terminal rows show (`rowStatus`), leaving out
  // terminals that report none, in row order.
  agentStatuses(w: SpaceInfo): AgentStatus[] {
    return this.listing(w)
      .map((row) => row.status)
      .filter((status): status is AgentStatus => status !== null);
  }

  // The most urgent status among a space's terminal rows, null without any.
  spaceStatus(w: SpaceInfo): AgentStatus | null {
    return topStatus(this.agentStatuses(w));
  }

  // Whether focus sits on one of the space's terminal rows: never when the
  // space is folded or the row's tab is (`tabFolded`).
  terminalRowFocused(w: SpaceInfo): boolean {
    const listing = this.listings.get(w.id);
    if (!listing || w.id in this.foldedSpaces) return false;
    const shown = focused()?.terminal;
    return terminalRowsOf([
      ...listing.tabs.flatMap((tab) => (tab.folded ? [] : tab.rows)),
      ...listing.loose,
    ]).some(({ step }) => step.node.terminal.address === shown);
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

  // The end of the name line of a space with rows under it (a tab, or a
  // loose terminal): a chevron that folds them and, folded, adds how many
  // agents they show at any depth in the most urgent one's color. Pressing
  // it neither selects nor drags the space.
  foldToggle(w: SpaceInfo, t: ThemeColors): Element | null {
    const listing = this.listings.get(w.id);
    if (!listing || (!listing.tabs.length && !listing.loose.length))
      return null;
    const keep = (_e: MouseButtonEvent, cx: Context) => cx.stop_propagation();
    const open = !(w.id in this.foldedSpaces);
    // A null `top` (no status ranks) indexes `t` as "null": no color, so dim.
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
      .text_color(open ? t.dim : (t[top as AgentStatus] ?? t.dim))
      .cursor_pointer()
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", keep)
      .on_click((_e, cx) => {
        cx.stop_propagation();
        this.setSpaceFolded(w, open);
        cx.notify();
      })
      .when(!open, (el) => el.child(String(this.agentStatuses(w).length)))
      .child(
        svg(`mods/workspace-chrome/chevron-${open ? "down" : "right"}.svg`)
          .size(11)
          .flex_none(),
      );
  }

  // The rows under an unfolded space: each tab's divider followed by its
  // terminal rows (a settled tab's divider dimmed, and its rows left out
  // while it is folded, `tabFolded`), then the loose terminal rows, each
  // terminal followed by the rows nested under it and then its finished
  // terminals' rows. Dividers start under the start of the space's name
  // (`TEXT_X`), and terminal rows are placed from there
  // (`terminalRowElement`). Each run of terminal rows (a tab's, or the loose
  // ones) is spaced by `TERMINAL_ROW_GAP`.
  terminalRows({ w }: SpaceRow, t: ThemeColors, now: number): Element[] {
    const listing = this.listings.get(w.id);
    if (!listing || w.id in this.foldedSpaces) return [];

    // A row's terminal is loose when no tab of the space shows it; one
    // without a pane at all says so.
    return [
      ...listing.tabs.flatMap(({ tab, rows, folded }) => [
        div()
          .id(`tab-divider-${tab.id}`)
          .pl(TEXT_X - ROW_X)
          .pr(8)
          .child(tabDivider(t, tab, { dim: tab.settled })),
        ...terminalRun(
          folded ? [] : rows.map((row) => this.listingRowElement(row, t, now)),
        ),
      ]),
      ...terminalRun(
        listing.loose.map((row) =>
          this.listingRowElement(row, t, now, {
            markPaneless: true,
          }),
        ),
      ),
    ];
  }

  // A machine's Elsewhere section, for its terminals no space holds
  // (`TreeMachine.elsewhere`): a small "ELSEWHERE" heading, then a row for
  // each, with the terminals each started nested under it, live then
  // finished, every live one
  // without a pane marked "no pane". The section is a little dimmed, as
  // terminals outside the spaces you work in, or as dim as the machine's
  // spaces while the machine is away (`isAway`). It has no fold of its own.
  // Null when the machine has no such terminals.
  elsewhereSection(
    machine: TreeMachine,
    isAway: boolean,
    t: ThemeColors,
    now: number,
  ): Element | null {
    const rows = listingRows(machine.elsewhere);
    if (!rows.length) return null;
    return v_flex()
      .id(`machine-elsewhere-${machine.name ?? "local"}`)
      .flex_none()
      .pl(ROW_X)
      .pt(4)
      .pb(4)
      .gap(ROW_GAP)
      .border_t(1)
      .border_color(t.border)
      .opacity(isAway ? 0.5 : 0.8)
      .child(
        div()
          .pl(TEXT_X - ROW_X)
          .pt(2)
          .text_size(10.5)
          .font_semibold()
          .text_color(t.dim)
          .child("ELSEWHERE"),
      )
      .children(
        terminalRun(
          rows.map((row) =>
            this.listingRowElement(row, t, now, {
              markPaneless: true,
            }),
          ),
        ),
      );
  }

  // A listing row in the sidebar: a live terminal's (`terminalRowElement`,
  // given `opts`) or a finished one's (`finishedRowElement`).
  listingRowElement(
    row: ListingRow,
    t: ThemeColors,
    now: number,
    opts?: { markPaneless?: boolean },
  ): Element {
    return row.kind === "terminal"
      ? this.terminalRowElement(row, t, now, opts)
      : this.finishedRowElement(row.step, t, now);
  }

  // A terminal's row in the sidebar, its content `terminalRow`'s, placed by
  // its depth (`terminalRowX`). Its second line names the checkout its
  // folder is in once that is known (`terminalFolderLine`).
  // Clicking it focuses its pane, or peeks at a terminal without one; the
  // focused terminal's row is filled. `opts.markPaneless` notes "no pane" on
  // a row without a pane.
  terminalRowElement(
    { step, status }: TerminalListing,
    t: ThemeColors,
    now: number,
    opts?: { markPaneless?: boolean },
  ): Element {
    const { node, depth } = step;
    const address = node.terminal.address;
    const pane = node.pane;
    const isFocused = address === (focused()?.terminal ?? null);
    const model = terminalRowModel(
      {
        ...node,
        status,
      },
      home(),
      this.commands.shown(node.terminal, now),
    );
    const font = settings().font_family;
    const since = node.info
      ? this.history.since(node.info) || null
      : (node.terminal.status_ms ?? null);
    // A hover style layers over the base style, so only rows that are not
    // focused get one; the focused row keeps its fill under the mouse.
    return h_flex()
      .id(`terminal-${address}`)
      .flex_none()
      .ml(terminalRowX(depth))
      .pl(TERMINAL_ROW_PAD_X)
      .pr(8)
      .rounded(6)
      .cursor_pointer()
      .when(isFocused, (el) => el.bg(t.hover))
      .when(!isFocused, (el) => el.hover((s) => s.bg(hoverFill(t, t.chrome))))
      .on_click(() =>
        pane
          ? run("pane.focus", { pane: pane.pane })
          : run("terminal.peek", { terminal: address }),
      )
      .child(
        terminalRow(t, model, now, {
          since,
          activeAt: this.history.activeAt(address),
          note: opts?.markPaneless && pane === null ? "no pane" : undefined,
          dimTitle: !isFocused && (status === null || status === "idle"),
          commandFont: typeof font === "string" ? font : undefined,
          folderLine: this.terminalFolderLine(node.terminal, status, t),
        }),
      );
  }

  // The second line of terminal `terminal`'s row when the folder it is in
  // now is in a checkout `Checkouts` has found (`terminalCheckoutLine`, its
  // badge by the terminal's agent status `status`, null for a plain
  // terminal); undefined otherwise, leaving the folder as the line.
  terminalFolderLine(
    terminal: TerminalEntry,
    status: AgentStatus | null,
    t: ThemeColors,
  ): Element | undefined {
    const place = terminalPlace(terminal);
    const g = place && this.checkouts.checkoutOf(JSON.stringify(place));
    if (!place || !g) return undefined;

    const [machine, cwd] = place;
    return terminalCheckoutLine(g, cwd, machine, status, t);
  }

  // A finished terminal's row in the sidebar, its content `finishedRow`'s,
  // placed as a live terminal's row at its depth (`terminalRowX`), so its
  // mark lines up with the icons. Clicking it goes to the
  // live terminal that started it: focuses that terminal's pane, or peeks at
  // it without one. Right-clicking it shows a "Remove" chip at its end
  // (`removeChipAddress`) until a press anywhere else; clicking the chip
  // removes the finished terminal (`removeFinished`).
  finishedRowElement(
    { finished, parent, depth }: TreeFinishedStep,
    t: ThemeColors,
    now: number,
  ): Element {
    const pane = parent.pane;
    const showsRemoveChip = this.removeChipAddress === finished.address;
    return h_flex()
      .id(`finished-${finished.address}`)
      .flex_none()
      .ml(terminalRowX(depth))
      .pl(TERMINAL_ROW_PAD_X)
      .pr(8)
      .relative()
      .rounded(6)
      .cursor_pointer()
      .hover((s) => s.bg(hoverFill(t, t.chrome)))
      .on_click((_e, cx) => {
        this.dismissRemoveChip(cx);
        if (pane) run("pane.focus", { pane: pane.pane });
        else run("terminal.peek", { terminal: parent.terminal.address });
      })
      .on_mouse_down("right", (_e, cx) => {
        this.removeChipAddress = finished.address;
        cx.notify();
      })
      .child(finishedRow(t, finished, now))
      .when(showsRemoveChip, (el) =>
        el
          .on_mouse_down_out((_e, cx) => this.dismissRemoveChip(cx))
          .child(this.removeChip(finished, t)),
      );
  }

  // The "Remove" chip at the end of a finished terminal's row, a badge in
  // the blocked color like the "conflict" one (`terminalCheckoutBadge`):
  // removing is the one action in the sidebar that deletes something.
  // Clicking it removes `finished` (`removeFinished`) without going to its
  // parent.
  removeChip(finished: FinishedTerminal, t: ThemeColors): Element {
    return div()
      .id(`finished-remove-${finished.address}`)
      .flex_none()
      .self_center()
      .ml(6)
      .h(16)
      .px(5)
      .flex()
      .items_center()
      .rounded(4)
      .bg((t.blocked + "26") as Color)
      .hover((s) => s.bg((t.blocked + "40") as Color))
      .text_size(10.5)
      .font_semibold()
      .text_color(t.blocked)
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_click((_e, cx) => {
        cx.stop_propagation();
        this.dismissRemoveChip(cx);
        this.removeFinished(finished, cx);
      })
      .child("Remove");
  }

  // Hides the "Remove" chip, if a row shows it.
  dismissRemoveChip(cx: Context): void {
    if (this.removeChipAddress === null) return;

    this.removeChipAddress = null;
    cx.notify();
  }

  // Removes the finished terminal `finished` with `hc rm`, then reads the
  // finished terminals again so its row goes. When `hc rm` exits non-zero
  // or cannot run, posts an error notification with the first line of what
  // it said.
  removeFinished(finished: FinishedTerminal, cx: Context): void {
    const title = `Couldn't remove ${finishedLabel(finished)}`;
    cx.spawn(async (cx) => {
      try {
        const r = await hc(["rm", finished.address]);
        if (r.code !== 0)
          notify({
            title,
            body: firstLine(r.stderr || r.stdout) || `hc rm exited ${r.code}`,
            level: "error",
          });
      } catch (e) {
        notify({
          title,
          body: firstLine(e instanceof Error ? e.message : String(e)),
          level: "error",
        });
      }

      this.finished.refresh(cx);
    });
  }

  render(): Element {
    const t = theme() as ThemeColors;
    const collapsed = narrow();
    const sp = spaces();
    assignSpaceColors(sp);

    const now = Date.now();
    const list = agents();
    const allTerminals = terminals() as unknown as TerminalEntry[];
    this.history.track(list, allTerminals, now);
    this.history.trackActivity(allTerminals, now);
    this.history.hold(list);
    this.pruneFoldedSpaces(sp);
    const tree = buildTree({
      terminals: allTerminals,
      agents: list,
      panes: panes(),
      spaces: sp,
      machines: this.machines,
      finished: this.finished.finished,
    });
    this.listings = new Map(
      tree.machines.flatMap((m) =>
        m.spaces.map((s) => [s.space.id, spaceListing(s)]),
      ),
    );
    const tray = needsYou(list, (a) => RANK[a.status] ?? 0);
    const terminalByAddress = new Map(allTerminals.map((k) => [k.address, k]));
    const labelOf = (a: AgentInfo) =>
      agentLabel({
        terminal: terminalByAddress.get(a.address) ?? { address: a.address },
        info: a,
        pane: null,
      });
    const waitsForOf = (a: AgentInfo) =>
      blockedKind({
        status: a.status,
        reportKind: terminalByAddress.get(a.address)?.report?.kind || null,
      });

    // Next/previous agent: "Needs you", then the tree in the machine order
    // `grouped` draws, folded machines and spaces included: the agents with a
    // pane among the terminal rows, each machine's Elsewhere rows after its
    // spaces', in row order. The focused agent
    // keeps its "Needs you" slot here after looking turns it from done to
    // idle (`orderRank`), so stepping on reaches the one after it, though the
    // tray itself drops it.
    const rows = this.ordered();
    const agentsWithPane = (listing: TerminalListing[]) =>
      listing
        .filter(
          ({ step }) => step.node.pane !== null && step.node.status !== null,
        )
        .map(({ step }) => step.node.terminal.address);
    const treeOrder = tree.machines.flatMap((m) => [
      ...rows
        .filter((r) => (r.w.machine ?? null) === m.name)
        .flatMap((r) => agentsWithPane(this.listing(r.w))),
      ...agentsWithPane(terminalRowsOf(listingRows(m.elsewhere))),
    ]);
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
          .children(this.grouped(t, collapsed, tree.machines, rows, now)),
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
              needsYouRows(
                tray,
                labelOf,
                waitsForOf,
                t,
                now,
                (a) => this.history.since(a),
                this.thisComputerName,
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

// A space's rows, grouped as the sidebar draws them: `tabs`, every tab of
// the space in order (empty ones included) with the rows of the terminals
// the tree places in it, then `loose`, the rows of the space's terminals in
// none of its tabs.
interface SpaceListing {
  // `folded` (`tabFolded`): the tab is settled with nothing in it needing
  // the person, so the sidebar draws its divider without its rows.
  tabs: { tab: TabInfo; rows: ListingRow[]; folded: boolean }[];
  loose: ListingRow[];
}

function spaceListing(treeSpace: TreeSpace): SpaceListing {
  return {
    tabs: treeSpace.tabs.map((treeTab) => ({
      tab: treeTab.tab,
      rows: listingRows(treeTab.terminals),
      folded: tabFolded(treeTab),
    })),
    loose: listingRows(treeSpace.loose),
  };
}

// One row the sidebar lists under a space or Elsewhere: a live terminal's
// (`TerminalListing`) or a finished terminal's (`FinishedListing`).
type ListingRow = TerminalListing | FinishedListing;

// One live terminal row: its `walkTree` step, with the depth it is indented
// by, and the status it shows (`rowStatus`).
interface TerminalListing {
  kind: "terminal";
  step: TreeTerminalStep;
  status: AgentStatus | null;
}

// One finished terminal row: its `walkTree` step, with the depth it is
// indented by and the live terminal it hangs under. It shows no status: rail
// status, fold counts and the agent order leave it out.
interface FinishedListing {
  kind: "finished";
  step: TreeFinishedStep;
}

// The rows of the top-level terminals `nodes` and every live and finished
// terminal nested under them, in `walkTree` order.
function listingRows(nodes: TreeTerminal[]): ListingRow[] {
  // The terminal last walked at each depth: a row's parent is the one a
  // level up.
  const ancestors: TreeTerminal[] = [];
  return [...walkTree(nodes)].map((step): ListingRow => {
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
      status: rowStatus(step.node, parent),
    };
  });
}

// The live terminal rows of `rows`, in their order.
function terminalRowsOf(rows: ListingRow[]): TerminalListing[] {
  return rows.filter((row): row is TerminalListing => row.kind === "terminal");
}

// The first line of `text`, without surrounding whitespace.
function firstLine(text: string): string {
  return text.trim().split("\n", 1)[0];
}

// How far right of `ROW_X` a terminal row's fill starts, in px, nested
// `depth` levels: `TERMINAL_ROW_INSET`, plus `DEPTH_INDENT` per level. A
// top-level row, under a space's name at `TEXT_X` (26), fills from x 18,
// after `TERMINAL_ROW_PAD_X` its stripe starts at x 20, and past the
// stripe's 10px column its icon at x 30.
function terminalRowX(depth: number): number {
  return TERMINAL_ROW_INSET + depth * DEPTH_INDENT;
}

// A run of terminal rows (`rows`, live and finished) stacked
// `TERMINAL_ROW_GAP` apart, as one element of the group, which spaces its
// own elements `ROW_GAP` apart; none when `rows` is empty, so an empty run
// adds no gap.
function terminalRun(rows: Element[]): Element[] {
  return rows.length
    ? [v_flex().flex_none().gap(TERMINAL_ROW_GAP).children(rows)]
    : [];
}
