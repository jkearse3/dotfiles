// The find hub: one popup listing spaces with their agents and plain
// terminals under a header for each machine, the rows that make a new
// terminal or space, and a preview of the selected row beside the list.
// `ctrl-b f`, `cmd-p`, the `palette` mod's "Find space, agent or terminal…"
// entry and the `desk-chrome` search button open it. With an empty query the
// list shows a space tree in the app's layout order (`findRows` in
// `rows.ts`): each of a space's tabs, empty ones included, starts with a
// divider as the sidebar draws one (`tabDivider` in `tree-rows.ts`), members
// are indented under their space and sub-terminals under their parents, and
// a terminal without a pane follows its space's tabs, without a divider,
// noted "no pane". Each Git worktree's or jj workspace's space is listed
// under its repo's main checkout with a branch mark, and each
// space row has a second line naming its checkout ("dotfiles / ws3"), which
// a query matches too, both
// from the checkouts the desk-spaces sidebar shares (`SPACE_CHECKOUTS_KEY`
// in `space-order.ts`); before the sidebar has shared a space's checkout,
// that space has neither. A settled tab's divider is dimmed, and while
// nothing in it needs the person (`tabFolded`) its terminal rows are left
// out, though a query still finds them. Typing filters it with fzf
// (`match.ts`) into a flat list, best match first, where each terminal and
// finished row names its space, and its machine when that is not this
// computer. Each terminal row shows its program's icon, and its label starts
// with its program's short name ("claude", "fish"), which a query also
// matches, so `claude` finds Claude Code agents.
// Terminal rows are drawn as the desk-spaces sidebar draws them
// (`terminalRow` in `tree-rows.ts`, from `terminalRowModel` in
// `labels.ts`). Every terminal row starts with a 3px stripe in the color
// of its state (`stripeColor` in `row-colors.ts`: an agent's status color,
// cyan for a plain terminal running a command, else grey). Its first line
// shows its program and title, an agent's ending with its status mark, and
// a dim second line
// shows the folder the terminal is in now, which a query matches too. An
// agent row's third line says what it is doing, else its status word, with
// the time since its status changed at its end. A blocked agent that says
// what it waits for ("permission", "question", "auth") shows that word
// there instead, in the blocked color, and a query matches it too. A plain
// terminal running a command, rather than sitting at its shell, shows that
// command on its third line in the terminal font, without a run time; a
// query does not match it. Rows
// other than terminal rows are one line, but for a space's checkout line.
// A terminal's preview heads its screen with where it is: its tab, its pane
// and its folder ("tab 2 · pane 1 · ~/src/app").
// After a terminal's nested rows come the terminals it started that have
// finished, oldest first, drawn as the sidebar draws them (`finishedRow` in
// `tree-rows.ts`: no stripe, a ✓, or a ✗ when it failed, its name, how it
// ended and when; on a flat list, also the terminal that started it, its
// space and its machine, as a terminal row there), from the finished
// terminals the sidebar shares (`FINISHED_TERMINALS_KEY` in
// `finished.ts`). A query matches one by its name, how it ended ("exit 1"), its space and the word
// "finished". Enter on one goes to the terminal that started it, and its
// preview heads its last screen with how and when it ended and its folder
// ("✗ exit 1 · 3m ago · ~/src/app"), or shows that line alone when the
// screen can't be read.
// Each machine's header (`machineHeader` in `tree-rows.ts`, named as the
// sidebar names it) shows even with nothing under it. While the machine is
// not connected, its header carries a badge saying so and the rows under it
// are dimmed. A machine's spaces follow its header, then its "ELSEWHERE"
// label over its terminals no space holds. Headers, tab dividers and labels
// are never selected and drop out while filtering.
// Each terminal row's status word is matched too, so `blocked` or `done`
// finds the agents that show it. ctrl-n toggles the needs-you filter
// (`needsYouRows` in `rows.ts`): while it is on, the list holds only the
// terminal rows showing blocked or done and the finished rows that failed,
// as a flat list in the tree's order where each row names its space (and
// machine) as a match does, and a query matches among them alone; with
// none, the list says "Nothing needs you". The footer marks the filter in
// the accent color while it is on.
// The selected row is filled with the theme's hover color; any other row
// under the mouse gets a fainter fill (`hoverFill` in `row-colors.ts`), so
// hovering never looks like a second selection and the selected row keeps
// its fill under the mouse.
// ↑/↓ or ctrl-j/ctrl-k move, Enter goes to the row, ctrl-u/ctrl-d scroll the
// preview, ctrl-x ends the row's terminal (agent or plain), removes its
// finished terminal with `hc rm` or closes its space after a y/n prompt,
// ctrl-i interrupts the row's terminal (both in `actions.ts`), Esc leaves. A footer names the keys that act on the
// selected row (`footerHints` in `view.ts`), or the prompt's keys while one
// shows (`promptHints`).
//
// fzf runs once per query rather than as a long-lived picker, so the hub
// draws its own rows from the app's live data, which updates the list while
// it is open, and still matches with fzf's matcher and query syntax. When
// fzf is missing or fails, the hub shows every row with a line saying why.
// The pure display arithmetic lives in `view.ts`.
//
// `agent-marks.ts`, `finished.ts`, `foreground.ts`, `labels.ts`, `names.ts`,
// `paths.ts`, `program-icon.ts`, `quiet.ts`, `row-colors.ts`,
// `space-order.ts`, `status.ts`, `terminals.ts`, `tree.ts` and `tree-rows.ts`
// beside this file are links to the shared copies in `mod-lib/`.

import { View, div, svg } from "gpui-kit";
import type {
  AsyncContext,
  Color,
  Context,
  Element,
  FocusHandle,
} from "gpui-kit";
import type { Props } from "gpui-shell";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import {
  agents,
  closeOverlay,
  exec,
  focused,
  hc,
  home,
  notify,
  panes,
  props,
  run,
  settings,
  setShared,
  shared,
  spaces,
  terminals,
  theme,
} from "herdr";
import type { SpaceInfo, Status } from "herdr";
import { closePrompt, interruptNotice } from "./actions.js";
import type { CloseAction } from "./actions.js";
import { duration } from "./agent-marks.js";
import { FINISHED_TERMINALS_KEY, readFinishedTerminals } from "./finished.js";
import {
  filterableRows,
  findRows,
  isSelectable,
  needsYouRows,
  unfoldedRows,
} from "./rows.js";
import type { FindRow, FindWorld } from "./rows.js";
import { LatestRequest, matchOrAll, planShownList } from "./match.js";
import type { Matchable } from "./match.js";
import { cliPath } from "./paths.js";
import { readSpaceCheckouts, SPACE_CHECKOUTS_KEY } from "./space-order.js";
import { hoverFill } from "./row-colors.js";
import {
  finishedRow,
  machineHeader,
  tabDivider,
  terminalRow,
} from "./tree-rows.js";
import type { TerminalEntry } from "./terminals.js";
import type { MachineEntry } from "./tree.js";
import {
  agentPreviewKey,
  cursorIndex,
  finishedPreviewHeader,
  followAgentPreview,
  footerHints,
  isWantedAgentRead,
  previewWindow,
  promptHints,
  rowHeight,
  rowOffsets,
  screenLines,
  selectableIndex,
  spaceTreePreview,
  terminalPreviewHeader,
  wheelSelectionIndex,
} from "./view.js";

const TITLE = "Find";

// The hub's height as a share of the window's, matching `overlay.height` in
// `mod.json`. That popup height is only a cap: a popup is as tall as its
// content, and the list and preview take their height from the popup, so the
// hub sets its own.
const WINDOW_HEIGHT_SHARE = 0.8;

// Every preview line's height, in logical px. List rows take theirs from
// `rowHeight`.
const LINE_H = 16;
// How far each nesting level indents a row with an empty query, in logical
// px: a space's members sit one level in, and sub-terminals one more per
// depth.
const DEPTH_INDENT = 16;
// How long the cursor rests on an agent before its screen is read, in ms, so
// moving through the list does not read every screen on the way.
const PREVIEW_DELAY_MS = 150;

// The theme's colors by name. The app's typings type `theme()` as
// `Record<string, string>`, though every value is a color.
type ThemeColors = Record<string, Color>;

// The fields of `hc machine ls --json` this mod reads.
interface MachineList {
  machines?: MachineEntry[];
}

// The fields of `hc server status --json` this mod reads: the name of this
// computer's herdr-core.
interface ServerStatus {
  core?: { name?: string };
}

// The latest fzf result: the rows of `input` matching `query`, by key, best
// first, or every row with `error` saying why matching failed.
interface MatchResult {
  query: string;
  input: Matchable[];
  keys: string[];
  error: string | null;
}

// An agent's screen as `hc read` last returned it, for the agent at
// `address` while it had the status in `key`; `lines` is null when the read
// failed with `error`.
interface AgentPreview {
  key: string;
  address: string;
  lines: string[] | null;
  error: string | null;
}

// The `y/n` question `ctrl-x` asked about the row with `key`: its `text`,
// and the `action` that `y` runs.
interface CloseQuestion {
  key: string;
  text: string;
  action: CloseAction;
}

const MARK: Record<string, Color> = {
  ansi6: "#22a99a",
  ansi3: "#e3814f",
  ansi4: "#5b8def",
  ansi5: "#8b7cf6",
  ansi2: "#3fae6a",
  ansi1: "#d9649a",
};

// Space colors, kept by space id in shared "space.colors": a theme
// color name ("ansi6") or a picked #rrggbb. A space seen without one gets
// the theme color fewest spaces use, once; every mod does the same in the
// same order, so they agree, and adding or renaming spaces moves nothing.
type SpaceColorChoices = Record<string, string>;
const PROJECT_COLORS = ["ansi6", "ansi3", "ansi4", "ansi5", "ansi2", "ansi1"];
function spaceColors(): SpaceColorChoices {
  const ids = new Set(spaces().map((p) => p.id));
  const kept = Object.fromEntries(
    Object.entries((shared("space.colors") as SpaceColorChoices) ?? {}).filter(
      ([id]) => ids.has(id),
    ),
  );
  let changed =
    Object.keys(kept).length !==
    Object.keys((shared("space.colors") as SpaceColorChoices) ?? {}).length;
  for (const p of spaces()) {
    if (kept[p.id] || p.name === "~") continue;
    const uses = (c: string) =>
      Object.values(kept).filter((v) => v === c).length;
    kept[p.id] = PROJECT_COLORS.reduce((best, c) =>
      uses(c) < uses(best) ? c : best,
    );
    changed = true;
  }
  if (changed) setShared("space.colors", kept);
  return kept;
}
function spaceColor(t: ThemeColors, p: SpaceInfo): Color {
  if (p.name === "~") return t.dim;
  const c = spaceColors()[p.id] ?? PROJECT_COLORS[0];
  return c.startsWith("#") ? (c as Color) : (MARK[c] ?? t[c]);
}

// The four statuses the theme has a color for.
const STATUS_WORDS: ReadonlySet<string> = new Set<Status>([
  "working",
  "blocked",
  "done",
  "idle",
]);

// The first line of `error`'s message.
function firstLine(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message.split("\n", 1)[0];
}

// Takes the finished terminal at `address`, just removed with `hc rm`, out of
// the shared finished terminals (`FINISHED_TERMINALS_KEY`), so views reading
// them stop listing it before the sidebar next reads the CLI; the sidebar
// notices the change and reads again (`followFinished` in
// `mods/desk-spaces/main.ts`). Writes only when the value held it, since
// `setShared` re-renders every mod.
function unshareFinished(address: string): void {
  const finished = readFinishedTerminals(shared(FINISHED_TERMINALS_KEY));
  const kept = finished.filter((f) => f.address !== address);
  if (kept.length !== finished.length) setShared(FINISHED_TERMINALS_KEY, kept);
}

export default class Find extends View {
  declare input: InputState;
  declare query: string;
  declare handle: FocusHandle;
  // Whether this copy is an open overlay. `herdr-app check` renders the mod
  // without one, and then it must not run `hc` or `exec`.
  declare live: boolean;
  // The machines `hc machine ls` lists, read once when the hub opens.
  declare machines: MachineEntry[];
  // What `hc server status` names this computer, read once when the hub
  // opens; null until it answers or when it fails.
  declare thisComputerName: string | null;
  // The terminal focused when the hub opened.
  declare focusedAtOpen: string | null;
  // fzf's store path, read on the first filtered query.
  declare fzfPath: string | null;

  declare matcher: LatestRequest;
  declare matched: MatchResult | null;
  // The match the list on screen answers or awaits, so a render does not
  // schedule it again.
  declare requested: { query: string; input: Matchable[] } | null;
  // The query whose list is on screen; while a newer query's match runs,
  // the older list stays.
  declare shownQuery: string;
  // Whether the needs-you filter is on (ctrl-n): the list holds only
  // `needsYouRows`.
  declare isNeedsYouOn: boolean;

  // The cursor: its index in `list`, the key of its row, and the query and
  // needs-you filter of the list it was placed in.
  declare at: number;
  declare selectedKey: string | null;
  declare cursorQuery: string;
  declare cursorNeedsYouOn: boolean;
  // The list the latest render drew, for the key and click handlers.
  declare list: FindRow[];
  // How far the row strip is scrolled, and the list's laid-out height, in
  // logical px.
  declare scroll: number;
  declare listHeight: number | undefined;

  // The app's data the latest render built its rows from.
  declare world: FindWorld;
  // The addresses of the finished terminals this hub removed or is removing
  // with `hc rm` (`removeFinished`), left out of the shared ones while
  // `hc rm` runs; once it succeeds the shared value drops them too
  // (`unshareFinished`). One whose removal fails is taken out again.
  declare removed: Set<string>;
  // The `y/n` question showing, if any. While it shows, every key answers it
  // instead of reaching the query.
  declare prompt: CloseQuestion | null;

  declare previewer: LatestRequest;
  declare preview: AgentPreview | null;
  // The agent preview key the latest scheduled read is for.
  declare previewWanted: string | null;
  // The key of the preview drawn last, so a new one starts unscrolled.
  declare previewShown: string | null;
  // How many lines the preview is scrolled away from its anchor end, and
  // which end that is.
  declare previewOffset: number;
  declare previewAnchor: "bottom" | "top";
  // Whether the preview drawn last holds more lines than fit, so
  // ctrl-u/ctrl-d scroll it.
  declare previewScrollable: boolean;
  // The preview's laid-out height in logical px.
  declare previewHeight: number;

  init(_props: Props | undefined, cx: AsyncContext): void {
    this.query = "";
    this.input = InputState.new({
      placeholder: "Find space, agent or terminal…",
    });
    this.input.on("change", (_e, cx) => {
      this.query = this.input.value();
      cx.notify();
    });
    this.input.on("submit", () => {
      if (!this.prompt) this.go(this.list[this.at]);
    });
    this.input.focus();
    cx.timer.after(600, () => this.input.focus());
    // Agent rows' times since a status change count in minutes.
    cx.timer.every(30000, (cx) => cx.notify());
    this.handle = cx.focus_handle();

    this.live = props()?.overlay != null;
    this.machines = [];
    this.thisComputerName = null;
    this.focusedAtOpen = focused()?.terminal ?? null;
    this.fzfPath = null;
    this.matcher = new LatestRequest();
    this.matched = null;
    this.requested = null;
    this.shownQuery = "";
    this.isNeedsYouOn = false;
    this.at = 0;
    this.selectedKey = null;
    this.cursorQuery = "";
    this.cursorNeedsYouOn = false;
    this.list = [];
    this.scroll = 0;
    this.prompt = null;
    this.removed = new Set();
    this.previewer = new LatestRequest();
    this.preview = null;
    this.previewWanted = null;
    this.previewShown = null;
    this.previewOffset = 0;
    this.previewAnchor = "top";
    this.previewHeight = 0;
    this.previewScrollable = false;

    if (this.live)
      cx.spawn(async (cx) => {
        try {
          const r = await hc(["machine", "ls", "--json"]);
          if (r.code === 0)
            this.machines =
              (JSON.parse(r.stdout) as MachineList).machines ?? [];
        } catch {
          // Without the machine list the hub shows only the machines its
          // spaces and terminals name, and offers no new remote spaces.
        }
        try {
          const r = await hc(["server", "status", "--json"]);
          if (r.code === 0)
            this.thisComputerName =
              (JSON.parse(r.stdout) as ServerStatus).core?.name || null;
        } catch {
          // Without it this computer's header says "This computer".
        }
        cx.notify();
      });
  }

  dismiss(): void {
    closeOverlay(props().overlay);
  }

  // Closes the hub and acts on `row`: shows its terminal or space, or makes
  // the new terminal or space. A finished row shows the live terminal that
  // started it: its pane, or a peek at it without one. A machine header, a
  // tab divider or an elsewhere label does nothing and leaves the hub open.
  go(row: FindRow | undefined): void {
    if (!row || !isSelectable(row)) return;
    this.dismiss();
    switch (row.kind) {
      case "terminal":
        if (row.model.status !== null) {
          run("agent.focus", { terminal: row.address });
          break;
        }
        // A plain terminal: show its tab, then focus its pane there.
        if (row.tab) run("tab.select", { id: row.tab });
        run("pane.focus", { terminal: row.address });
        break;
      case "finished":
        if (row.parentTab) {
          run("tab.select", { id: row.parentTab });
          run("pane.focus", { terminal: row.parent });
        } else run("terminal.peek", { terminal: row.parent });
        break;
      case "space":
        run("space.select", { id: row.space.id });
        break;
      case "new-terminal":
        run("tab.new");
        break;
      case "new-space":
        // The folder picker (`space-new`) lists this computer's folders, so a
        // space on another machine is made without one.
        if (row.machine) run("space.new", { machine: row.machine });
        else run("mod.open", { name: "space-new" });
        break;
      case "machine":
      case "tab":
      case "elsewhere":
        break;
    }
  }

  // Runs `prompt`'s action when its row is still among the rows; a row that
  // vanished while the prompt showed is left alone. The hub stays open, and
  // the next render drops the closed row.
  answerYes(prompt: CloseQuestion, cx: Context): void {
    if (!findRows(this.world).some((r) => r.key === prompt.key)) return;

    const action = prompt.action;
    if (action.command === "hc rm")
      this.removeFinished(action.args.terminal, cx);
    else run(action.command, action.args);
  }

  // Removes the finished terminal at `address` with `hc rm`, hiding its row
  // at once (`removed`) and, once the command succeeds, taking it out of the
  // shared finished terminals (`unshareFinished`) so the sidebar and a
  // reopened hub stop listing it. When the command fails, its row comes back
  // and the person is told why. Does nothing without an overlay.
  removeFinished(address: string, cx: Context): void {
    if (!this.live) return;

    this.removed.add(address);
    cx.spawn(async (cx) => {
      let error: string | null;
      try {
        const r = await hc(["rm", address]);
        error =
          r.code === 0
            ? null
            : firstLine(r.stderr.trim()) || `hc rm exited with ${r.code}`;
      } catch (e) {
        error = firstLine(e);
      }
      if (error === null) {
        unshareFinished(address);
        return;
      }

      this.removed.delete(address);
      notify({
        title: TITLE,
        body: error,
        level: "error",
      });
      cx.notify();
    });
  }

  // Interrupts the terminal `row` names, agent or plain, with
  // `hc interrupt` and tells the person when it shows no sign of stopping or
  // the command fails. The hub stays open. Does nothing on other rows, or
  // without an overlay.
  interrupt(row: FindRow | undefined, cx: Context): void {
    if (row?.kind !== "terminal" || !this.live) return;

    const { address } = row;
    const { label } = row.model;
    cx.spawn(async () => {
      try {
        const r = await hc(["interrupt", "--json", "--timeout", "3", address]);
        const notice = interruptNotice(label, r);
        if (notice)
          notify({
            title: TITLE,
            ...notice,
          });
      } catch (e) {
        notify({
          title: TITLE,
          body: firstLine(e),
          level: "error",
        });
      }
    });
  }

  // The list to show for `rows`, as `planShownList` decides: every row but
  // folded tabs' terminal rows (`unfoldedRows`) for a blank query, else
  // fzf's match over the rows a query can match (`filterableRows`). While
  // the needs-you filter is on, `needsYouRows` stands in for both. A match
  // not yet known is scheduled, and the list on screen stays until it
  // arrives, without the rows the current filter leaves out.
  shownList(rows: FindRow[], cx: Context): FindRow[] {
    const filterable = this.isNeedsYouOn
      ? needsYouRows(rows)
      : filterableRows(rows);
    const plan = planShownList(this.query, filterable, {
      matched: this.matched,
      requested: this.requested,
      shownQuery: this.shownQuery,
    });
    if (plan.invalidate) this.matcher.invalidate();
    this.requested = plan.requested;
    this.shownQuery = plan.shownQuery;

    const start = plan.start;
    if (start) {
      cx.timer.after(0, (cx) =>
        cx.spawn((cx) =>
          this.runMatch(cx, start.query, start.input, filterable),
        ),
      );
    }

    if (!plan.shown) return this.isNeedsYouOn ? filterable : unfoldedRows(rows);
    const byKey = new Map(filterable.map((r) => [r.key, r]));
    return plan.shown.keys.flatMap((k) => byKey.get(k) ?? []);
  }

  async runMatch(
    cx: AsyncContext,
    query: string,
    input: Matchable[],
    rows: FindRow[],
  ): Promise<void> {
    const r = await this.matcher.run(() => this.matchWork(query, rows));
    if (r.stale) return;

    this.matched = {
      query,
      input,
      keys: r.value.rows.map((row) => row.key),
      error: r.value.error,
    };
    cx.notify();
  }

  // `rows` matching `query`, or every row with the reason matching failed.
  async matchWork(
    query: string,
    rows: FindRow[],
  ): Promise<{ rows: FindRow[]; error: string | null }> {
    try {
      this.fzfPath ??= await cliPath("fzf");
    } catch (e) {
      return {
        rows: [...rows],
        error: firstLine(e),
      };
    }
    return matchOrAll(exec, this.fzfPath, query, rows);
  }

  // Schedules a read of the agent at `address`'s screen for preview `key`,
  // after the cursor has rested on it for `PREVIEW_DELAY_MS`, while the hub
  // is live. The read runs, and its screen is kept, only while `key` is
  // still `previewWanted`.
  wantAgentPreview(key: string, address: string, cx: Context): void {
    if (!this.live) return;

    cx.timer.after(PREVIEW_DELAY_MS, (cx) => {
      if (!isWantedAgentRead(this.previewWanted, key)) return;
      cx.spawn(async (cx) => {
        let preview: AgentPreview;
        try {
          const r = await this.previewer.run(() =>
            hc(["read", address, "--lines", "0"]),
          );
          if (r.stale) return;
          preview =
            r.value.code === 0
              ? {
                  key,
                  address,
                  lines: screenLines(r.value.stdout),
                  error: null,
                }
              : {
                  key,
                  address,
                  lines: null,
                  error:
                    firstLine(r.value.stderr.trim()) ||
                    `hc read exited with ${r.value.code}`,
                };
        } catch (e) {
          preview = {
            key,
            address,
            lines: null,
            error: firstLine(e),
          };
        }
        // A read the selection has since left is dropped.
        if (!isWantedAgentRead(this.previewWanted, key)) return;
        this.preview = preview;
        cx.notify();
      });
    });
  }

  render(cx: Context) {
    const t = theme() as ThemeColors;

    const world: FindWorld = {
      terminals: terminals() as unknown as TerminalEntry[],
      agents: agents(),
      panes: panes(),
      spaces: spaces(),
      machines: this.machines,
      finished: readFinishedTerminals(shared(FINISHED_TERMINALS_KEY)).filter(
        (f) => !this.removed.has(f.address),
      ),
      checkouts: readSpaceCheckouts(shared(SPACE_CHECKOUTS_KEY)),
      home: home(),
    };
    const rows = findRows(world);
    const list = this.shownList(rows, cx);
    const isFiltered = this.shownQuery.trim() !== "";
    // The needs-you list is flat, like a match.
    const isNested = !isFiltered && !this.isNeedsYouOn;
    const matchError =
      isFiltered && this.matched?.query === this.shownQuery
        ? this.matched.error
        : null;

    this.at = cursorIndex(
      list.map((r) => r.key),
      this.selectedKey,
      this.at,
      this.shownQuery === this.cursorQuery &&
        this.isNeedsYouOn === this.cursorNeedsYouOn,
    );
    this.at = selectableIndex(list.map(isSelectable), this.at, 1);
    this.cursorQuery = this.shownQuery;
    this.cursorNeedsYouOn = this.isNeedsYouOn;
    this.selectedKey = list[this.at]?.key ?? null;
    this.list = list;
    this.world = world;
    const selected = list[this.at];

    // One continuous strip: each row at a fixed y, below the rows before it.
    // Scrolling moves the strip only as far as it takes to keep the selected
    // row in view, so the arrows can't run the selection off the list.
    const heights = list.map(rowHeight);
    const offsets = rowOffsets(heights);
    const total = offsets[list.length];
    const height = this.listHeight ?? total;
    const maxScroll = Math.max(0, total - height);
    this.scroll = Math.max(0, Math.min(this.scroll, maxScroll));
    if (selected) {
      const top = offsets[this.at];
      const bottom = offsets[this.at + 1];
      if (top < this.scroll) this.scroll = top;
      if (bottom > this.scroll + height) this.scroll = bottom - height;
    }
    const isVisible = (i: number) =>
      offsets[i + 1] > this.scroll && offsets[i] < this.scroll + height;
    const now = Date.now();
    const dimText = (text: string) =>
      div().flex_none().text_size(11).text_color(t.dim).child(text);

    // A row under a machine `hc machine ls` reports in a state other than
    // connected is dimmed, as the sidebar dims it; the header's badge says
    // why. A terminal is under its space's machine, or under its own
    // machine's elsewhere label.
    const awayMachines = new Set(
      rows.flatMap((r) =>
        r.kind === "machine" &&
        r.machine.state !== null &&
        r.machine.state !== "connected"
          ? [r.machine.name]
          : [],
      ),
    );
    const isUnderAwayMachine = (r: FindRow): boolean => {
      const machine = machineOver(r);
      return machine !== null && awayMachines.has(machine);
    };

    const rowElement = (r: FindRow, i: number): Element => {
      const isSelected = i === this.at;
      const base = h_flex()
        .id(`find-${r.key}`)
        .absolute()
        .left(4)
        .right(4)
        .top(offsets[i] - this.scroll)
        .h(heights[i])
        .px(10)
        .rounded(7)
        .gap(10)
        .items_center()
        .when(r.key === this.prompt?.key, (el) =>
          el.border_1().border_color(t.blocked),
        )
        .when(isUnderAwayMachine(r), (el) => el.opacity(0.5))
        // Machine headers, tab dividers and elsewhere labels only label the
        // rows under them.
        .when(isSelectable(r), (el) =>
          el
            .cursor_pointer()
            // A hover style layers over the base style, so only rows that are
            // not selected get one; the selected row keeps its fill under the
            // mouse.
            .when(isSelected, (el) => el.bg(t.hover))
            .when(!isSelected, (el) =>
              el.hover((s) => s.bg(hoverFill(t, t.popover))),
            )
            .on_click(() => {
              this.at = i;
              this.selectedKey = r.key;
              this.go(r);
            }),
        );
      const name = (text: string) =>
        div().flex_1().min_w(0).truncate().text_color(t.foreground).child(text);

      switch (r.kind) {
        case "terminal":
          return terminalRowElement(base, r);
        case "finished":
          // Indented as a terminal row at its depth; on a flat list it names
          // the terminal that started it and its place instead.
          return base
            .when(isNested, (el) => el.pl(10 + (1 + r.depth) * DEPTH_INDENT))
            .child(
              finishedRow(t, r.finished, now, {
                parentHint: isNested ? undefined : r.parentLabel,
                hint: isNested ? undefined : placeHint(r),
              }),
            );
        case "machine":
          return base.child(
            machineHeader(t, r.machine, now, {
              thisComputerName: this.thisComputerName,
            }),
          );
        case "tab":
          // A divider starts where its space's top-level terminal rows do.
          return base
            .when(isNested, (el) => el.pl(10 + DEPTH_INDENT))
            .child(
              v_flex()
                .flex_1()
                .min_w(0)
                .child(tabDivider(t, r.tab, { dim: r.tab.settled })),
            );
        case "elsewhere":
          return base.child(
            div()
              .text_size(10.5)
              .font_semibold()
              .text_color(t.dim)
              .child("ELSEWHERE"),
          );
        case "space": {
          // A worktree's space nested under its repo's has a branch mark in
          // front; a flat list of matches has no nesting.
          const space = r.space;
          return base
            .when(isNested && r.tree !== null, (el) =>
              el.child(
                svg("mods/workspace-chrome/branch.svg")
                  .size(13)
                  .flex_none()
                  .text_color(t.dim),
              ),
            )
            .child(
              h_flex()
                .size(18)
                .flex_none()
                .rounded(5)
                .bg(spaceColor(t, space))
                .items_center()
                .justify_center()
                .text_size(10.5)
                .font_bold()
                .text_color("#ffffff")
                .child([...space.name][0]?.toUpperCase() ?? "?"),
            )
            .child(
              v_flex()
                .flex_1()
                .min_w(0)
                .line_height(1.3)
                .child(
                  h_flex()
                    .min_w(0)
                    .gap(10)
                    .items_center()
                    .child(name(space.name))
                    .when(space.machine !== null, (el) =>
                      el.child(dimText(space.machine ?? "")),
                    ),
                )
                .when(r.checkoutLine !== null, (el) =>
                  el.child(
                    div()
                      .min_w(0)
                      .truncate()
                      .text_size(11.5)
                      .text_color(t.dim)
                      .child(r.checkoutLine ?? ""),
                  ),
                ),
            );
        }
        case "new-terminal":
        case "new-space":
          return base
            .text_color(t.muted)
            .child(div().w(12).flex_none().child("+"))
            .child(r.text);
      }
    };

    // Where a terminal or finished row is, for a flat list where no header
    // above it says so: its space's name (or "elsewhere") and its machine.
    const placeHint = (
      r: Extract<FindRow, { kind: "terminal" | "finished" }>,
    ): string =>
      [r.space?.name ?? "elsewhere", r.machine].filter(Boolean).join("  ");

    const font = settings().font_family;
    const terminalFont = typeof font === "string" ? font : undefined;

    // A terminal row, drawn as the desk-spaces sidebar draws one
    // (`terminalRow` from `tree-rows.ts`). With an empty query it indents by
    // its depth; a match names its space and machine instead. The parent is
    // named wherever indentation doesn't show it: on every match, and on a
    // top-level row listed apart from its parent. The terminal focused when the
    // hub opened is semibold, and an idle agent other than it is muted.
    const terminalRowElement = (
      base: Element,
      r: Extract<FindRow, { kind: "terminal" }>,
    ): Element => {
      const isFocusedAtOpen = r.address === this.focusedAtOpen;
      return base
        .when(isNested, (el) => el.pl(10 + (1 + r.depth) * DEPTH_INDENT))
        .child(
          terminalRow(t, r.model, now, {
            since: r.since,
            parentHint:
              r.parentLabel !== null && (!isNested || r.depth === 0)
                ? r.parentLabel
                : undefined,
            note: r.note ?? undefined,
            hint: isNested ? undefined : placeHint(r),
            emphasized: isFocusedAtOpen,
            dimTitle: r.model.status === "idle" && !isFocusedAtOpen,
            commandFont: terminalFont,
          }),
        );
    };

    const previewLines = this.previewLines(selected, rows, t, cx);

    return v_flex()
      .id("find")
      .track_focus(this.handle)
      .w_full()
      .h((window.viewport_size().height / zoom()) * WINDOW_HEIGHT_SHARE)
      .p(18)
      .gap(10)
      .bg(t.popover)
      .text_size(13)
      .on_key_down((e, cx) => {
        const k = e.key;
        // fzf's ctrl-j/ctrl-k: control alone, so cmd/alt/shift chords pass.
        const m = e.modifiers;
        const isControlOnly = m.control && !m.platform && !m.alt && !m.shift;
        if (this.prompt) {
          const isYes =
            (e.keystroke === "y" || e.key_char === "y") &&
            !m.control &&
            !m.platform &&
            !m.alt;
          if (isYes) this.answerYes(this.prompt, cx);
          this.prompt = null;
          cx.stop_propagation();
          cx.notify();
          return;
        }
        if (k === "x" && isControlOnly) {
          const row = this.list[this.at];
          const p = row ? closePrompt(row, this.world) : null;
          if (row && p)
            this.prompt = {
              key: row.key,
              ...p,
            };
          cx.stop_propagation();
          cx.notify();
          return;
        }
        if (k === "i" && isControlOnly) {
          this.interrupt(this.list[this.at], cx);
          cx.stop_propagation();
          return;
        }
        if (k === "n" && isControlOnly) {
          this.isNeedsYouOn = !this.isNeedsYouOn;
          cx.stop_propagation();
          cx.notify();
          return;
        }
        const isDown = k === "down" || (k === "j" && isControlOnly);
        const isUp = k === "up" || (k === "k" && isControlOnly);
        const isOlder = k === "u" && isControlOnly;
        const isNewer = k === "d" && isControlOnly;
        if (k === "escape") return this.dismiss();
        if (isDown || isUp) {
          // Wraps at the ends and skips machine headers, tab dividers and
          // elsewhere labels in the direction of travel; an empty list has
          // nothing to move to.
          const n = this.list.length;
          if (n > 0) {
            this.at = selectableIndex(
              this.list.map(isSelectable),
              (this.at + (isDown ? 1 : n - 1)) % n,
              isDown ? 1 : -1,
            );
            this.selectedKey = this.list[this.at].key;
          }
        } else if (isOlder || isNewer) {
          // Half a preview's height; the next render clamps the offset.
          const step = Math.max(1, Math.floor(this.previewHeight / LINE_H / 2));
          const awayFromAnchor = isOlder === (this.previewAnchor === "bottom");
          this.previewOffset += awayFromAnchor ? step : -step;
        } else return;
        cx.stop_propagation();
        cx.notify();
      })
      .child(
        h_flex()
          .items_center()
          .child(
            div()
              .flex_1()
              .text_size(15)
              .font_semibold()
              .text_color(t.foreground)
              .child(TITLE),
          ),
      )
      .child(
        h_flex()
          .h(36)
          .flex_none()
          .px(10)
          .gap(8)
          .items_center()
          .rounded(9)
          .border_1()
          .border_color(t.accent)
          .bg(t.background)
          .child(
            svg("mods/workspace-chrome/search.svg").size(15).text_color(t.dim),
          )
          .child(
            Input.new(this.input)
              .flex_1()
              .h_full()
              .text_size(12.8)
              .text_color(t.foreground),
          ),
      )
      .when(this.prompt !== null, (el) =>
        el.child(
          div()
            .flex_none()
            .text_size(12)
            .font_semibold()
            .text_color(t.blocked)
            .child(this.prompt?.text ?? ""),
        ),
      )
      .when(matchError !== null, (el) =>
        el.child(
          div()
            .flex_none()
            .truncate()
            .text_size(12)
            .text_color(t.blocked)
            .child(`Matching failed, so every row shows: ${matchError}`),
        ),
      )
      .child(
        h_flex()
          .flex_1()
          .min_h(0)
          .gap(12)
          .child(
            div()
              .id("find-list")
              .w("45%")
              .flex_none()
              .h_full()
              .min_h(0)
              .overflow_hidden()
              .on_size_change((size, cx) => {
                this.listHeight = size.height / zoom();
                cx.notify();
              })
              .on_scroll_wheel((e, cx) => {
                this.scroll = Math.max(
                  0,
                  Math.min(this.scroll - e.delta.y, maxScroll),
                );
                // The selection follows the wheel, so the next frame doesn't
                // scroll back to it.
                this.at = wheelSelectionIndex(
                  this.list.map(isSelectable),
                  this.list.map(rowHeight),
                  this.scroll,
                  height,
                  this.at,
                );
                this.selectedKey = this.list[this.at]?.key ?? null;
                cx.notify();
              })
              .when(this.isNeedsYouOn && list.length === 0, (el) =>
                el.child(
                  div()
                    .px(14)
                    .pt(8)
                    .text_size(12)
                    .text_color(t.dim)
                    .child("Nothing needs you"),
                ),
              )
              .children(
                list.flatMap((r, i) =>
                  isVisible(i) ? [rowElement(r, i)] : [],
                ),
              ),
          )
          .child(
            v_flex()
              .id("find-preview")
              .flex_1()
              .min_w(0)
              .h_full()
              .min_h(0)
              .pl(12)
              .border_l(1)
              .border_color(t.border)
              .overflow_hidden()
              .text_size(12)
              .when(typeof font === "string", (el) =>
                el.font_family(font as string),
              )
              .on_size_change((size, cx) => {
                this.previewHeight = size.height / zoom();
                cx.notify();
              })
              .children(previewLines),
          ),
      )
      .child(
        h_flex()
          .id("find-footer")
          .flex_none()
          .gap(14)
          .text_size(11)
          .children(
            (this.prompt
              ? promptHints(this.prompt.action)
              : footerHints(selected, this.previewScrollable, this.isNeedsYouOn)
            ).map((hint) =>
              h_flex()
                .gap(4)
                .child(
                  div()
                    .text_color(hint.isOn ? t.accent : t.foreground)
                    .child(hint.keys),
                )
                .child(
                  div()
                    .text_color(hint.isOn ? t.accent : t.dim)
                    .child(hint.label),
                ),
            ),
          ),
      );
  }

  // The preview of `row` that fits the preview's height: a space's tree of
  // terminals from the unfiltered `rows`, top-anchored, or a live or
  // finished terminal's screen, bottom-anchored like a terminal, under a
  // header line. Machine headers, tab dividers,
  // elsewhere labels and new rows have none. Scrolling resets when the preview
  // changes. Records in `previewScrollable` whether the lines overflow the
  // preview.
  previewLines(
    row: FindRow | undefined,
    rows: readonly FindRow[],
    t: ThemeColors,
    cx: Context,
  ): Element[] {
    this.previewScrollable = false;

    const line = (text: string, color: Color) =>
      div()
        .h(LINE_H)
        .flex_none()
        .whitespace_nowrap()
        .overflow_hidden()
        .text_color(color)
        .child(text);
    // `reserved` lines of the preview's height hold a header above `lines`.
    const fitting = <T>(
      key: string,
      lines: readonly T[],
      anchor: "bottom" | "top",
      reserved = 0,
    ): T[] => {
      if (this.previewShown !== key) this.previewOffset = 0;
      this.previewShown = key;
      this.previewAnchor = anchor;
      const visible = Math.max(
        0,
        Math.floor(this.previewHeight / LINE_H) - reserved,
      );
      const w = previewWindow(
        lines.length,
        visible,
        this.previewOffset,
        anchor,
      );
      this.previewOffset = w.offset;
      this.previewScrollable = visible > 0 && lines.length > visible;
      return lines.slice(w.start, w.end);
    };

    // The preview follows the selection: leaving a terminal, live or
    // finished, forgets its screen, so returning to it reads the screen
    // afresh.
    const screenOf =
      row?.kind === "terminal"
        ? {
            address: row.address,
            status: row.model.status,
          }
        : row?.kind === "finished"
          ? {
              address: row.finished.address,
              status: null,
            }
          : null;
    const followed = followAgentPreview(screenOf, {
      preview: this.preview,
      previewWanted: this.previewWanted,
    });
    this.preview = followed.preview;
    this.previewWanted = followed.previewWanted;
    if (followed.readKey !== null && screenOf)
      this.wantAgentPreview(followed.readKey, screenOf.address, cx);

    if (row?.kind === "space") {
      // A status word in its theme color; a plain terminal's line in the
      // foreground; any other word, such as a sub-agent's raw status, muted.
      const color = (status: string | null): Color =>
        status === null
          ? t.foreground
          : STATUS_WORDS.has(status)
            ? t[status]
            : t.muted;
      const lines = spaceTreePreview(row.space, rows);
      return fitting(row.key, lines, "top").map((l) =>
        line(l.text, color(l.status)),
      );
    }
    if (!screenOf || (row?.kind !== "terminal" && row?.kind !== "finished")) {
      this.previewShown = null;
      return [];
    }

    // Where a live terminal is heads its screen: its tab, pane and folder;
    // how and when a finished one ended, and its folder, heads its last. A
    // line wider than the pane is cut from the left, so the folder's last
    // segments stay visible.
    const headerText =
      row.kind === "terminal"
        ? terminalPreviewHeader(row)
        : finishedPreviewHeader(
            row.finished,
            row.finished.finishedMs > 0
              ? duration(Date.now() - row.finished.finishedMs)
              : null,
            home(),
          );
    const header = [line(headerText, t.dim).truncate().text_ellipsis_start()];
    const key = agentPreviewKey(screenOf.address, screenOf.status);
    const preview = this.preview;
    if (!preview) {
      this.previewShown = null;
      return [...header, line("…", t.dim)];
    }
    // A finished terminal whose screen can't be read shows its header alone.
    if (preview.lines === null)
      return row.kind === "finished"
        ? header
        : [...header, line(preview.error ?? "", t.blocked)];
    return [
      ...header,
      ...fitting(key, preview.lines, "bottom", header.length).map((l) =>
        line(l, t.foreground),
      ),
    ];
  }
}

// The machine whose header `row` sits under, by name; null for this
// computer, and for a machine header and the new rows, which no header
// dims.
function machineOver(row: FindRow): string | null {
  switch (row.kind) {
    case "terminal":
    case "finished":
      return row.space ? row.space.machine : row.machine;
    case "space":
    case "tab":
      return row.space.machine;
    case "elsewhere":
      return row.machine;
    case "machine":
    case "new-terminal":
    case "new-space":
      return null;
  }
}

// The app's zoom, which `on_size_change` and window sizes are divided by to
// get the logical px the layout is written in.
function zoom(): number {
  const z = settings().zoom;
  return typeof z === "number" && z > 0 ? z : 1;
}
