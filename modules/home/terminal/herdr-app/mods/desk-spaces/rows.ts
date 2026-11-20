// What the desk-spaces sidebar draws in its rows: the space colors, a space's
// rail entry and checkout lines, and the "Needs you" tray. The terminal rows
// themselves are `tree-rows.ts` `terminalRow`'s. Plain functions; the view (`main.ts`)
// passes in what each needs from its state.

import { div } from "gpui-kit";
import type { Color, Element } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, shared, setShared, home } from "herdr";
import type { AgentInfo, SpaceInfo } from "herdr";
import { programIcon } from "./program-icon.js";
import { duration, statusMark } from "./agent-marks.js";
import { checkoutText } from "./space-order.js";
import { hoverFill } from "./row-colors.js";
import type { Checkout, GitCheckout, JjCheckout } from "./checkouts.js";
import type { AgentStatus } from "./status.js";
import { machineOf } from "./terminals.js";

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
// How much further in a nested terminal row starts than its parent's, in px
// per level of nesting, its fill included.
export const DEPTH_INDENT = 16;
// Where the focus bar sits: midway between the tick column and the rows'
// text, which starts at `TEXT_X`.
const BAR_X = 17;
export const TEXT_X = 26;
// How far a top-level terminal row's fill starts right of `ROW_X`, in px,
// so its rounded fill sits inside the space's rows rather than flush with
// the tick column; with `TERMINAL_ROW_PAD_X` and the 10px column
// `terminalRow` draws its stripe in, its stripe starts at x 20 and its icon
// at x 30, 4px right of the space's name at `TEXT_X`.
export const TERMINAL_ROW_INSET = 4;
// The space between a terminal row's fill edge and its state stripe, in px.
export const TERMINAL_ROW_PAD_X = 2;
// The space between stacked rows, so two filled rows (one hovered, one
// focused) read as two rounded shapes rather than one block.
export const ROW_GAP = 5;
// The space between stacked terminal rows (a tab's, the loose ones, or
// Elsewhere's), wider than `ROW_GAP` so each terminal, with its stripe,
// reads as a unit of its own.
export const TERMINAL_ROW_GAP = 7;
// The "Needs you" rows' height: three two-line rows and the gaps between.
const TRAY_H = 3 * 44 + 2 * ROW_GAP;

// The mark of a space row holding focus: a short rounded accent bar at
// `BAR_X`. Its row must be `relative()` and begin at `ROW_X`. A terminal
// row holding focus shows it by its fill alone.
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
    .hover((s) => s.bg(hoverFill(t, t.chrome)))
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
  // A null status indexes as "null", which no theme color has.
  return t[status as AgentStatus] ?? t.unknown;
}

// The checkout line under every space's name, shown whether or not the
// space was renamed so rows read alike: `checkoutText` of space `w` and its
// checkout `g` ("dotfiles / ws3"), null when that is. The `space-rename-all`
// mod's rows say the same (its `checkoutLabel` and `checkout`); change them
// together.
export function checkoutLine(
  w: SpaceInfo,
  g: Checkout | null,
  t: ThemeColors,
): Element | null {
  const text = checkoutText(w, g, home());
  if (!text) return null;
  return div()
    .min_w(0)
    .truncate()
    .text_size(11.5)
    .text_color(t.dim)
    .child(text);
}

// A badge for the checkout line of a quiet space, by the statuses of its
// agents (`agentStatuses`: some, none working or blocked) and checkout `g`:
// "conflict" when its jj
// checkout has one, else "review" when it has unshipped work (jj: edits in @
// or revisions after the nearest bookmark; git: commits ahead of upstream).
// Null otherwise.
export function checkoutBadge(
  agentStatuses: AgentStatus[],
  g: Checkout | null,
  t: ThemeColors,
): Element | null {
  const quiet =
    agentStatuses.length > 0 &&
    !agentStatuses.some((s) => s === "working" || s === "blocked");
  if (!g || !quiet) return null;
  const conflict = Boolean(g.jj && g.conflict);
  const unshipped = g.jj
    ? // The jj distance counts @ itself, whose content `modified` covers.
      g.modified || (g.direction === "↑" && g.distance > 1)
    : g.ahead > 0;
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

// The "Needs you" section: a heading with how many, then blocked agents and
// done ones, newest first; `since` gives when an agent's status last changed.
// `labelOf` gives what an agent is (`agentLabel`), and `waitsForOf` what a
// blocked one waits for (`blockedKind`), null when it does not say. With
// none, the heading shows "0", all dim, over a dim "Nothing waiting"; the
// label turns amber when one does. A row's second line names its agent's
// space, and for an agent on another machine that machine too ("~ · box",
// `machineOf` its address); a row on this computer names its space alone.
export function needsYouRows(
  needsYou: AgentInfo[],
  labelOf: (a: AgentInfo) => string,
  waitsForOf: (a: AgentInfo) => string | null,
  t: ThemeColors,
  now: number,
  since: (a: AgentInfo) => number,
): Element[] {
  // Each row as the tree draws an agent, two lines: what the agent is, then
  // the space it is in and, when remote, its machine, beside that space's
  // color in a thin bar. The tray mixes every machine's agents, so the
  // machine tells apart two spaces of the same name. A blocked agent says
  // what it waits for ("permission"), else "needs you", in its status color,
  // a done one has a dot, and both say how long ago. The tree above fills the
  // focused row; here focus only brightens the text.
  const row = (a: AgentInfo) => {
    const pic = programIcon(a.program, 14, t.foreground);
    const when = since(a);
    const machine = machineOf(a.address);
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
      .hover((s) => s.bg(hoverFill(t, t.chrome)))
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
      .when(Boolean(pic), (el) => el.child(div().mt(2).child(pic!)))
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
                  .child(labelOf(a)),
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
                      .child(waitsForOf(a) ?? "needs you")
                  : div().flex_none().child(statusMark(t, a.status)),
              ),
          )
          .child(
            h_flex()
              .min_w(0)
              .gap(4)
              .items_center()
              .text_size(11)
              .text_color(a.focused ? t.muted : t.dim)
              .child(div().min_w(0).truncate().child(a.space_name))
              // The machine does not shrink, so a long space name truncates
              // first and the machine stays readable; it is capped at the
              // line's width, so it truncates only when it alone is wider.
              .when(Boolean(machine), (el) =>
                el.child(
                  div()
                    .flex_shrink_0()
                    .max_w_full()
                    .truncate()
                    .child(`\u00b7 ${machine}`),
                ),
              ),
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
