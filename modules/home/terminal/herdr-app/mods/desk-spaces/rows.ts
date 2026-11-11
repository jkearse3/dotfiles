// What the desk-spaces sidebar draws in its rows: the space colors, a space's
// rail entry and checkout lines, agent and sub-agent rows with their status
// marks, and the "Needs you" tray. Plain functions; the view (`main.ts`)
// passes in what each needs from its state.

import { div, image, svg } from "gpui-kit";
import type { Color, Element } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, shared, setShared, home } from "herdr";
import type { AgentInfo, Program, SpaceInfo, Status } from "herdr";
import { place } from "./paths.js";
import { base } from "./checkouts.js";
import type { Checkout, GitCheckout, JjCheckout } from "./checkouts.js";
import { kidStatus } from "./agents.js";
import type { AgentSpot, AgentStatus, CrewMember, SubAgent } from "./agents.js";

// The theme's colors by name. The app's typings type `theme()` as
// `Record<string, string>`, though every value is a color.
export type ThemeColors = Record<string, Color>;

// One space in the sidebar's list, in the order `ordered` gives: the space,
// its index in `spaces()`, its checkout (null when not a repo or not known
// yet), and, for a worktree listed under its repo's main checkout, its branch
// mark ("├─", "└─" for the last), else null.
export interface SpaceRow {
  w: SpaceInfo;
  i: number;
  g: Checkout | null;
  tree: "├─" | "└─" | null;
}

// Space colors by space id, as shared "space.colors" keeps them: a theme
// color name ("ansi6") or a picked hex color.
type SpaceColorChoices = Record<string, string>;

// What a stored color name looks like on an avatar (the same in every mod
// that draws space avatars): one strong color per hue, light and dark alike.
const MARK: Record<string, Color> = {
  ansi6: "#22a99a",
  ansi3: "#e3814f",
  ansi4: "#5b8def",
  ansi5: "#8b7cf6",
  ansi2: "#3fae6a",
  ansi1: "#d9649a",
};

// Gives each space in `sp` without a stored `space.colors` entry the palette
// color fewest spaces use (none for the home space "~", which avatarFill draws
// teal), and drops entries of spaces that are gone. Writes `space.colors` only
// when that changes it.
export function assignSpaceColors(sp: SpaceInfo[]): void {
  const palette = ["ansi6", "ansi3", "ansi4", "ansi5", "ansi2", "ansi1"];
  const ids = new Set(sp.map((p) => p.id));
  const kept = Object.fromEntries(
    Object.entries((shared("space.colors") as SpaceColorChoices) ?? {}).filter(
      ([id]) => ids.has(id),
    ),
  );
  let changed =
    Object.keys(kept).length !==
    Object.keys((shared("space.colors") as SpaceColorChoices) ?? {}).length;
  for (const p of sp) {
    if (kept[p.id] || p.name === "~") continue;
    const uses = (c: string) =>
      Object.values(kept).filter((v) => v === c).length;
    kept[p.id] = palette.reduce((best, c) => (uses(c) < uses(best) ? c : best));
    changed = true;
  }
  if (changed) setShared("space.colors", kept);
}

// A space's avatar color: its stored `space.colors` name or hex, else teal.
export const avatarFill = (spaceId: string, t: ThemeColors): Color => {
  const color =
    ((shared("space.colors") as SpaceColorChoices) ?? {})[spaceId] ?? "ansi6";
  return color.startsWith("#") ? (color as Color) : (MARK[color] ?? t[color]);
};

// Where a space's color tick sits, from the left of its group: the column the
// active space's rail runs down too.
export const TICK_X = 8;
// Where a group's rows begin: right of the tick column, so a row's rounded
// hover and focus fills never run under the tick or rail.
export const ROW_X = 14;
// Where the focus bar sits: midway between the tick column and the rows'
// text, which starts at `TEXT_X`.
const BAR_X = 17;
export const TEXT_X = 26;
// The space between stacked rows, so two filled rows (one hovered, one
// focused) read as two rounded shapes rather than one block.
export const ROW_GAP = 5;
// The "Needs you" rows' height: three two-line rows and the gaps between.
const TRAY_H = 3 * 44 + 2 * ROW_GAP;

// A hex color "#rgb", "#rrggbb" or "#rrggbbaa" as [r, g, b, a], or null.
function channels(hex: string | undefined): number[] | null {
  const m = /^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.exec(hex ?? "");
  if (!m) return null;
  const h = m[1].length === 3 ? [...m[1]].map((c) => c + c).join("") : m[1];
  return [0, 2, 4, 6].map((i) =>
    i < h.length ? parseInt(h.slice(i, i + 2), 16) : 255,
  );
}

// A hovered row's fill: halfway from the sidebar's own color to the focused
// row's `t.hover`, so a hovered row next to the focused one reads as a lighter
// touch, not a second selection. `t.hover` itself when either color isn't hex.
export function hoverFill(t: ThemeColors): Color {
  const a = channels(t.chrome);
  const b = channels(t.hover);
  if (!a || !b) return t.hover;
  const mix = a.map((v, i) => Math.round((v + b[i]) / 2));
  return `#${mix.map((v) => v.toString(16).padStart(2, "0")).join("")}`;
}

// The mark of the one row holding focus: a short rounded accent bar at
// `BAR_X`. Its row must be `relative()` and begin at `ROW_X`.
export const focusBar = (t: ThemeColors): Element =>
  div()
    .absolute()
    .left(BAR_X - ROW_X)
    .top(7)
    .bottom(7)
    .w(2)
    .rounded(1)
    .bg(t.accent);

// On the rail a space speaks up with its agents' most urgent status
// (`status`, null without agents).
export function compact(
  { w, i }: SpaceRow,
  t: ThemeColors,
  status: AgentStatus | null,
): Element {
  return h_flex()
    .id(`space-${w.id}`)
    .h(26)
    .flex_none()
    .justify_center()
    .gap(4)
    .when(w.active, (el) => el.bg(t.raised))
    .hover((s) => s.bg(hoverFill(t)))
    .on_click(() => run("space.select", { id: w.id }))
    .child(
      div()
        .text_color(w.active ? t.foreground : t.muted)
        .child(String(i + 1)),
    )
    .child(div().text_color(tone(t, status)).child(glyph(status)));
}

// A space speaks up only when something in it needs you. The rail draws its
// status as one text character (`glyph`) in a status color (`tone`); agent
// rows draw theirs with `statusMark`: a spinner, a "!" badge, a ring or a dot.
// They stay separate because one mark for both would change what either shows.
function glyph(status: AgentStatus | null): string {
  return status === "blocked" || status === "done" ? "●" : "·";
}

function tone(t: ThemeColors, status: AgentStatus | null): Color {
  return t[status] ?? t.unknown;
}

// The checkout line under every space's name, shown whether or not the
// space was renamed so rows read alike: the folder its first terminal's
// checkout (or, outside a repo, the folder itself) is named after, after its
// repo ("dotfiles / ws3", just "dotfiles" when they match). Null only when
// there is no folder to name. The `space-rename-all` mod's rows say the
// same (its `checkoutLabel` and `checkout`); change them together.
export function checkoutLine(
  w: SpaceInfo,
  g: Checkout | null,
  t: ThemeColors,
): Element | null {
  const path = g ? g.top : place(w);
  const folder = !w.machine && path === home() ? "~" : base(path ?? "");
  const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();
  if (!folder) return null;
  const text = !g
    ? folder
    : same(g.name, folder)
      ? g.name
      : `${g.name} / ${folder}`;
  return div()
    .min_w(0)
    .truncate()
    .text_size(11.5)
    .text_color(t.dim)
    .child(text);
}

// A badge for the checkout line of a quiet space, by its `crew` (agents
// there, none working or blocked) and checkout `g`: "conflict" when its jj
// checkout has one, else "review" when it has unshipped work (jj: edits in @
// or revisions after the nearest bookmark; git: commits ahead of upstream).
// Null otherwise.
export function checkoutBadge(
  crew: CrewMember[],
  g: Checkout | null,
  t: ThemeColors,
): Element | null {
  const quiet =
    crew.length > 0 &&
    !crew.some((m) => m.status === "working" || m.status === "blocked");
  if (!g || !quiet) return null;
  const conflict = Boolean(g.jj && g.conflict);
  const unshipped = g.jj
    ? // The jj distance counts @ itself, whose content `modified` covers.
      g.modified || (g.direction === "↑" && g.distance > 1)
    : (g as GitCheckout).ahead > 0;
  if (!conflict && !unshipped) return null;
  const color = conflict ? t.ansi1 : t.accent;
  return div()
    .flex_none()
    .h(16)
    .px(5)
    .flex()
    .items_center()
    .rounded(4)
    .bg((color + "26") as Color)
    .text_size(10.5)
    .font_semibold()
    .text_color(color)
    .when(!conflict, (el) => el.opacity(0.75))
    .child(conflict ? "conflict" : "review");
}

// The repo status line under the name, only what's unusual:
// "herdr \u00b7 spike \u21912 \u21931". The repo goes when `quietRepo` (a
// worktree row under its repo, or a checkout line above that names it) or
// when the name already says it; the branch goes when the name says it (a
// worktree is named after its branch), and master/main go: nearly every
// space is on one. Null when nothing is left to show, which keeps the row
// shorter.
export function gitTail(
  g: GitCheckout,
  quietRepo: boolean,
  name: string,
  t: ThemeColors,
): Element | null {
  const raw = g.branch ?? "detached";
  const same = (a: string) => a.toLowerCase() === name.toLowerCase();
  const branch = same(raw) || raw === "master" || raw === "main" ? "" : raw;
  const repo = quietRepo || same(g.name) ? "" : g.name;
  const where = [repo, branch].filter(Boolean).join(" \u00b7 ");
  if (!where && !g.ahead && !g.behind) return null;
  return h_flex()
    .min_w(0)
    .gap(5)
    .items_center()
    .text_size(11.5)
    .text_color(t.dim)
    .when(Boolean(where), (el) =>
      el.child(div().min_w(0).truncate().child(where)),
    )
    .when(g.ahead > 0, (el) =>
      el.child(div().flex_none().text_color(t.ansi2).child(`\u2191${g.ahead}`)),
    )
    .when(g.behind > 0, (el) =>
      el.child(
        div().flex_none().text_color(t.ansi1).child(`\u2193${g.behind}`),
      ),
    );
}

// The second line under the name for a jj checkout, never empty, in the
// terminal prompt's words and colors: the nearest bookmark (purple, "(+1b)"
// when more share it), how far @ is from it (cyan \u2191 after it, \u2193
// before it), a conflict (red \u26a0) and edits in @ (yellow \u25cf). The
// change ID shows only without a bookmark, where nothing else says where @
// is. The repo shows as for git.
export function jjTail(
  g: JjCheckout,
  quietRepo: boolean,
  name: string,
  t: ThemeColors,
): Element {
  const same = (a: string) => a.toLowerCase() === name.toLowerCase();
  const repo = quietRepo || same(g.name) ? "" : g.name;
  return h_flex()
    .min_w(0)
    .gap(5)
    .items_center()
    .text_size(11.5)
    .text_color(t.dim)
    .when(Boolean(repo), (el) => el.child(div().flex_none().child(repo)))
    .child(
      g.bookmark
        ? div()
            .min_w(0)
            .truncate()
            .font_semibold()
            .text_color(t.ansi5)
            .child(g.bookmark)
        : div().flex_none().child(g.change),
    )
    .when(Boolean(g.bookmark) && g.distance > 0, (el) =>
      el.child(
        div()
          .flex_none()
          .text_color(t.ansi6)
          .child(`${g.direction}${g.distance}`),
      ),
    )
    .when(g.conflict, (el) =>
      el.child(div().flex_none().text_color(t.ansi1).child("\u26a0")),
    )
    .when(g.modified, (el) =>
      el.child(div().flex_none().text_color(t.ansi3).child("\u25cf")),
    );
}

// An agent's row, its lines in the order you read them, beside its icon,
// each one line, cut off at its end, and whole when hovered:
// - what it is (`agentName`), with the time since its status changed and
//   the status itself at the row's end (no time while it works: its spinner
//   says so);
// - what it is doing now ("Reading the docs") while it says, else its turn
//   count ("turn 3");
// - where it is: its tab (`tabText`), cut off, and "· pane 2" at the end
//   of the line, under the time and status, when its tab holds more than
//   one agent. The pane counts every pane of the tab in the app's pane order,
//   which follows how the tab was split, not where the panes now sit on
//   screen.
// `since` is when its status last changed (ms, `AgentHistory.since`).
export function agentRow(
  { a, label, spot, activity, turn }: CrewMember,
  indent: number,
  t: ThemeColors,
  now: number,
  since: number,
): Element {
  const pic = icon(a.program, 14, t.foreground);
  const when = a.status === "working" ? 0 : since;
  const idle = a.status === "idle" && !a.focused;
  const doing = activity || (turn != null ? `turn ${turn}` : null);
  return h_flex()
    .id(`agent-${a.address}`)
    .flex_none()
    .py(6)
    .pl(indent - ROW_X)
    .pr(8)
    .gap(8)
    .items_start()
    .relative()
    .rounded(6)
    .text_size(12.5)
    .cursor_pointer()
    .hover((s) => s.bg(hoverFill(t)))
    .when(a.focused, (el) => el.bg(t.hover).child(focusBar(t)))
    .on_click(() => run("pane.focus", { pane: a.pane }))
    .when(Boolean(pic), (el) => el.child(div().mt(2).child(pic)))
    .child(
      v_flex()
        .flex_1()
        .min_w(0)
        .gap(2)
        .line_height(1.3)
        .child(
          h_flex()
            .min_w(0)
            .gap(6)
            .items_center()
            .child(
              div()
                .id(`agent-name-${a.address}`)
                .flex_1()
                .min_w(0)
                .truncate()
                .text_color(idle ? t.muted : t.foreground)
                .tooltip(label)
                .child(label),
            )
            .when(Boolean(when), (el) =>
              el.child(
                div()
                  .flex_none()
                  .text_size(11)
                  .text_color(t.dim)
                  .child(duration(now - when)),
              ),
            )
            .child(div().flex_none().child(statusMark(t, a.status))),
        )
        .when(Boolean(doing), (el) =>
          el.child(
            div()
              .id(`agent-doing-${a.address}`)
              .min_w(0)
              .truncate()
              .text_size(11.5)
              .text_color(activity ? t.muted : t.dim)
              .tooltip(doing)
              .child(doing),
          ),
        )
        .child(
          h_flex()
            .min_w(0)
            .gap(6)
            .text_size(11)
            .text_color(t.dim)
            .child(
              div()
                .id(`agent-tab-${a.address}`)
                .flex_1()
                .min_w(0)
                .truncate()
                .tooltip(tabText(spot))
                .child(tabText(spot)),
            )
            .when(spot.pane != null, (el) =>
              el.child(div().flex_none().child(`\u00b7 pane ${spot.pane}`)),
            ),
        ),
    );
}

// An agent's tab as the tab bar names it: "tab 1", or a name someone gave it.
function tabText(spot: AgentSpot): string {
  return spot.named ? spot.tab : `tab ${spot.tab}`;
}

// A sub-agent's row: `s` a `tree` entry, `shown` the focused agent's
// address, `listed` the agent statuses `gatherAgents` returns.
export function subRow(
  t: ThemeColors,
  s: SubAgent,
  shown: string | null,
  indent: number,
  listed: Map<string, Status>,
): Element {
  const k = s.t;
  const st = kidStatus(k, listed);
  const pic = icon(k.program, 14, t.foreground);
  const on = k.address === shown;
  return h_flex()
    .id(`sub-${k.address}`)
    .pl(indent - ROW_X)
    .pr(8)
    .relative()
    .rounded(6)
    .h(26)
    .flex_none()
    .gap(0)
    .items_center()
    .text_size(12.5)
    .hover((s) => s.bg(hoverFill(t)))
    .when(on, (el) => el.bg(t.hover).child(focusBar(t)))
    .on_click(() => run("terminal.peek", { terminal: k.address }))
    .children(
      s.lines.map((l) =>
        div()
          .self_start()
          .mt(-4 - ROW_GAP)
          .w(9)
          .h(17 + ROW_GAP)
          .mr(4)
          .flex_none()
          .when(Boolean(l), (el) => el.border_l(1.5).border_color(t.input))
          .when(l === "└" || l === "├", (el) => el.border_b(1.5).rounded_bl(6)),
      ),
    )
    .when(Boolean(pic), (el) => el.child(div().mr(8).child(pic)))
    .child(
      div()
        .flex_1()
        .truncate()
        .text_color(on ? t.foreground : t.muted)
        .child(k.name || k.template || k.program?.name || k.address),
    )
    .child(statusMark(t, st));
}

// An agent status as the shipped agents list draws it in priority view: a
// spinner for working, a "!" for blocked, a dot for done, a ring for idle.
// The rail's one-character `glyph` and `tone` stay separate from this.
function statusMark(t: ThemeColors, status: AgentStatus | null): Element {
  if (status === "working")
    return svg("mods/workspace-chrome/spinner.svg")
      .size(12)
      .mx(1)
      .flex_none()
      .text_color(t.working)
      .spin(900);
  if (status === "blocked")
    return div()
      .size(14)
      .flex_none()
      .flex()
      .items_center()
      .justify_center()
      .rounded(4)
      .bg((t.blocked + "26") as Color)
      .text_size(10.5)
      .font_bold()
      .text_color(t.blocked)
      .child("!");
  if (status === "idle")
    return div()
      .size(7)
      .mx(3)
      .flex_none()
      .rounded(4)
      .border(1.5)
      .border_color(t.idle ?? t.dim);
  return div()
    .size(7)
    .mx(3)
    .flex_none()
    .rounded(4)
    .bg(status === "done" ? (t.done ?? t.dim) : ((t.dim + "00") as Color));
}

// `duration` and `icon` are copied from the shipped `agents` mod.

function duration(ms: number): string {
  const m = Math.floor(ms / 60000);
  if (m < 1) return "<1m";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}

// The agent's icon from the app's program table: a one-color glyph or a
// picture.
function icon(
  p: Program | undefined,
  size: number,
  color: Color,
): Element | null {
  if (!p?.icon) return null;
  return p.tint
    ? svg(p.icon).size(size).flex_none().text_color(color)
    : image(p.icon).w(size).h(size).flex_none();
}

// The "Needs you" section: a heading with how many, then blocked agents and
// done ones, newest first; `since` gives when an agent's status last changed.
// With none, the heading shows "0", all dim, over a dim "Nothing waiting";
// the label turns amber when one does.
export function needsYouRows(
  needsYou: AgentInfo[],
  byAddress: Map<string, CrewMember>,
  t: ThemeColors,
  now: number,
  since: (a: AgentInfo) => number,
): Element[] {
  // Each row as the tree draws an agent, two lines: what the agent is, then
  // the space it is in, beside that space's color in a thin bar. A blocked
  // agent says "needs you" in its status color, a done one has a dot, and
  // both say how long ago. The tree above fills the focused row; here focus
  // only brightens the text.
  const row = (a: AgentInfo) => {
    const pic = icon(a.program, 14, t.foreground);
    const when = since(a);
    return h_flex()
      .id(`needs-${a.address}`)
      .flex_none()
      .py(6)
      .px(8)
      .gap(8)
      .items_start()
      .rounded(6)
      .text_size(12.5)
      .cursor_pointer()
      .hover((s) => s.bg(hoverFill(t)))
      .on_click(() => run("pane.focus", { pane: a.pane }))
      .child(
        div()
          .w(2)
          .self_stretch()
          .my(1)
          .flex_none()
          .rounded(1)
          .bg(avatarFill(a.space, t)),
      )
      .when(Boolean(pic), (el) => el.child(div().mt(2).child(pic)))
      .child(
        v_flex()
          .flex_1()
          .min_w(0)
          .gap(2)
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
                  .text_color(t.foreground)
                  .when(a.focused, (el) => el.font_semibold())
                  .child(byAddress.get(a.address)?.label ?? a.address),
              )
              .when(Boolean(when), (el) =>
                el.child(
                  div()
                    .flex_none()
                    .text_size(11)
                    .text_color(t.dim)
                    .child(duration(now - when)),
                ),
              )
              .child(
                a.status === "blocked"
                  ? div()
                      .flex_none()
                      .text_size(11)
                      .font_semibold()
                      .text_color(t.blocked)
                      .child("needs you")
                  : div().flex_none().child(statusMark(t, a.status)),
              ),
          )
          .child(
            div()
              .min_w(0)
              .truncate()
              .text_size(11)
              .text_color(a.focused ? t.muted : t.dim)
              .child(a.space_name),
          ),
      );
  };
  return [
    h_flex()
      .id("needs-you")
      .h(24)
      .flex_none()
      .px(8)
      .gap(6)
      .items_center()
      .text_size(10.5)
      .font_semibold()
      .child(
        div()
          .text_color(needsYou.length ? t.blocked : t.dim)
          .child("NEEDS YOU"),
      )
      .child(div().text_color(t.dim).child(String(needsYou.length))),
    // The rows sit in a fixed height of three rows, so the tree above never
    // changes height; more scroll, with a bar. With none, a dim line says so.
    v_flex()
      .id("needs-you-rows")
      .h(TRAY_H)
      .flex_none()
      .gap(ROW_GAP)
      .overflow_y_scrollbar()
      .when(!needsYou.length, (el) =>
        el.child(
          div()
            .px(8)
            .pt(4)
            .text_size(11.5)
            .text_color(t.dim)
            .child("Nothing waiting"),
        ),
      )
      .children(needsYou.map(row)),
  ];
}
