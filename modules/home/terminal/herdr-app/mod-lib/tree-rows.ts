// How a view draws the rows of the shared tree (`tree.ts`): a machine's
// header (`machineHeader`), a tab's divider (`tabDivider`), a live
// terminal's row (`terminalRow`, from what `labels.ts` `terminalRowModel`
// says it shows) and a finished terminal's row (`finishedRow`). The
// desk-spaces sidebar draws its machines, tabs and terminals with them.
//
// These functions draw a row's content only. The caller places the row and
// gives it what makes it interactive: its element id, padding, click
// handling, and hover and selection fills.
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/tree-rows.ts` -> `../../mod-lib/tree-rows.ts`), and the
// herdr-app-mods build copies the file in place of the link and strips its
// types to `tree-rows.js`. The app refuses imports that leave a mod's own
// folder; `./tree-rows.js` beside the importing file is allowed. The
// `./agent-marks.js`, `./finished.js` and `./program-icon.js` this file
// imports must be linked beside it too, with what they import (`labels.ts`
// and `tree.ts` give only types).

import { div, svg } from "gpui-kit";
import type { Color, Element } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import type { TabInfo } from "herdr";
import { duration, statusMark } from "./agent-marks.js";
import { finishedLabel, finishedOutcome } from "./finished.js";
import type { FinishedTerminal } from "./finished.js";
import type { TerminalRowDetail, TerminalRowModel } from "./labels.js";
import { programIcon } from "./program-icon.js";
import type { TreeMachine } from "./tree.js";

// The start of a machine's header row, in small dim text: a monitor icon
// for this computer or a server icon for another machine, then its name
// (`opts.thisComputerName` for this computer, "This computer" without one),
// then, while `hc machine ls` reports it in a state other than connected, a
// badge with that state and how long it has been in it ("needs login ·
// 14m"; the state alone without `sinceMs`). `opts.narrow` draws the icon
// alone, for the sidebar's rail. The name grows to fill the width, so the
// caller's controls appended after it sit at the row's end. `now` is the
// time in ms since the epoch. `t` is the theme's colors by name (`theme()`).
export function machineHeader(
  t: Record<string, Color>,
  machine: Pick<TreeMachine, "name" | "state" | "sinceMs">,
  now: number,
  opts?: { thisComputerName?: string | null; narrow?: boolean },
): Element {
  const icon = svg(
    `mods/workspace-chrome/${machine.name === null ? "monitor" : "server"}.svg`,
  )
    .size(13)
    .flex_none();
  if (opts?.narrow) return icon;

  const name = machine.name ?? opts?.thisComputerName ?? "This computer";
  const state =
    machine.state !== null && machine.state !== "connected"
      ? machine.state.replace(/_/g, " ")
      : null;
  const badge =
    state !== null && machine.sinceMs !== null
      ? `${state} · ${duration(now - machine.sinceMs)}`
      : state;
  return h_flex()
    .flex_1()
    .min_w(0)
    .gap(7)
    .items_center()
    .text_size(11)
    .text_color(t.dim)
    .child(icon)
    .child(div().flex_1().min_w(0).truncate().font_semibold().child(name))
    .when(badge !== null, (el) =>
      el.child(
        div()
          .flex_none()
          .px(5)
          .rounded(4)
          .bg((t.dim + "26") as Color)
          .text_size(10.5)
          .child(badge ?? ""),
      ),
    );
}

// A thin line (18px high) that starts a tab's rows: the tab's name in small
// dim text, then a 1px rule filling the rest of the width ("1 ─────"). An
// unnamed tab shows its position, which is its `name`; a named one shows its
// position before its name ("2 notes ─────"). `dim` fades the whole line,
// for a tab that asks for less attention. `t` is the theme's colors by name
// (`theme()`).
export function tabDivider(
  t: Record<string, Color>,
  tab: TabInfo,
  opts?: { dim?: boolean },
): Element {
  const text = tab.named ? `${tab.index} ${tab.name}` : tab.name;
  return h_flex()
    .h(18)
    .flex_none()
    .min_w(0)
    .gap(6)
    .items_center()
    .when(Boolean(opts?.dim), (el) => el.opacity(0.5))
    .child(
      div()
        .flex_none()
        .max_w(160)
        .truncate()
        .text_size(10.5)
        .text_color(t.dim)
        .child(text),
    )
    .child(div().flex_1().min_w(0).h(1).bg(t.border));
}

// A live terminal's row content, from `model` (`terminalRowModel`), its
// lines cut off at their end unless said otherwise. After the program's
// icon (an empty square without one, so labels align), up to three lines:
// - a first line with the program's short name (`programName`) semibold,
//   then its `title` when it has one, `opts.parentHint` ("↳ lead"),
//   `opts.hint`, `opts.note`, and for an agent its status mark;
// - a second line, always, with the folder it is in now (`folder`) dim, cut
//   from the left so the folder's last segments stay;
// - for an agent, a third line with what it is doing (`detail`: what a
//   blocked agent waits for in the blocked color, its activity muted, its
//   status word dim), and at its end the time since `opts.since` (none
//   while it works, its spinner says so, or without `since`);
// - for a plain terminal running a command (a "command" `detail`), a third
//   line with the command in cyan (the theme's `ansi6`) in
//   `opts.commandFont`, at the size of an agent's third line so the row
//   keeps its height, and at its end, dim, how long it has run (none
//   without its `since`).
// `opts.emphasized` makes the title semibold and `opts.dimTitle` mutes it.
// `now` is the time in ms since the epoch. `t` is the theme's colors by
// name (`theme()`). The content keeps 6px above and below.
export function terminalRow(
  t: Record<string, Color>,
  model: TerminalRowModel,
  now: number,
  opts: TerminalRowOptions,
): Element {
  const icon =
    programIcon(model.program ?? undefined, ICON_SIZE, t.foreground) ??
    div().size(ICON_SIZE).flex_none();
  const isAgent = model.status !== null;
  const dimText = (text: string) =>
    div().flex_none().text_size(11).text_color(t.dim).child(text);

  // The title fills the width between the program's name and what follows,
  // so the hints and the status mark sit at the line's end.
  const firstLine = h_flex()
    .min_w(0)
    .gap(6)
    .items_center()
    .when(model.programName !== null, (el) =>
      el.child(
        div()
          .flex_none()
          .font_semibold()
          .text_color(t.foreground)
          .child(model.programName ?? ""),
      ),
    )
    .child(
      div()
        .id(`terminal-label-${model.address}`)
        .flex_1()
        .min_w(0)
        .truncate()
        .text_color(opts.dimTitle ? t.muted : t.foreground)
        .when(Boolean(opts.emphasized), (d) => d.font_semibold())
        .tooltip(model.label)
        .child(model.title ?? ""),
    )
    .when(Boolean(opts.parentHint), (el) =>
      el.child(dimText(`↳ ${opts.parentHint}`)),
    )
    .when(Boolean(opts.hint), (el) => el.child(dimText(opts.hint ?? "")))
    .when(Boolean(opts.note), (el) => el.child(dimText(opts.note ?? "")))
    .when(isAgent, (el) =>
      el.child(div().flex_none().child(statusMark(t, model.status))),
    );

  const secondLine = div()
    .min_w(0)
    .overflow_hidden()
    .whitespace_nowrap()
    .text_ellipsis_start()
    .text_size(11)
    .text_color(t.dim)
    .child(model.folder ?? "");
  const thirdLine =
    model.detail === null
      ? null
      : detailLine(t, model.detail, model, now, opts);

  return h_flex()
    .flex_1()
    .min_w(0)
    .py(ROW_PAD_Y)
    .items_start()
    .text_size(12.5)
    .child(div().flex_none().mt(2).mr(8).child(icon))
    .child(
      v_flex()
        .flex_1()
        .min_w(0)
        .gap(2)
        .line_height(1.3)
        .child(firstLine)
        .child(secondLine)
        .children(thirdLine === null ? [] : [thirdLine]),
    );
}

// A `terminalRow`'s third line, saying `detail` for the terminal `model`
// describes, then at its end, for an agent, how long it has been in its
// status; for a command, how long it has run.
function detailLine(
  t: Record<string, Color>,
  detail: TerminalRowDetail,
  model: Pick<TerminalRowModel, "address" | "status">,
  now: number,
  opts: Pick<TerminalRowOptions, "since" | "commandFont">,
): Element {
  const textColor =
    detail.kind === "command"
      ? t.ansi6
      : detail.kind === "blocked"
        ? t.blocked
        : detail.kind === "activity"
          ? t.muted
          : t.dim;
  const changedAt =
    detail.kind === "command"
      ? detail.since
      : model.status === "working"
        ? null
        : (opts.since ?? null);
  const time = changedAt !== null ? duration(now - changedAt) : null;
  const font = detail.kind === "command" ? opts.commandFont : undefined;

  return h_flex()
    .min_w(0)
    .gap(6)
    .items_center()
    .child(
      div()
        .id(`terminal-detail-${model.address}`)
        .flex_1()
        .min_w(0)
        .truncate()
        .text_size(11.5)
        .text_color(textColor)
        .when(detail.kind === "blocked", (d) => d.font_semibold())
        .when(font !== undefined, (d) => d.font_family(font ?? ""))
        .tooltip(detail.text)
        .child(detail.text),
    )
    .when(time !== null, (el) =>
      el.child(
        div()
          .flex_none()
          .text_size(11)
          .text_color(t.dim)
          .child(time ?? ""),
      ),
    );
}

// What a caller adds to a `terminalRow` beyond its model.
export interface TerminalRowOptions {
  // When its status last changed, in ms since the epoch; null or absent when
  // unknown.
  since?: number | null;
  // A dim word after the title saying how it is held ("no pane").
  note?: string;
  // Dim text after the title that places it, such as its space.
  hint?: string;
  // Its parent's label, for a row that does not show its parent above it.
  parentHint?: string;
  // Draws the title semibold.
  emphasized?: boolean;
  // Draws the title muted, for a row that asks for less attention.
  dimTitle?: boolean;
  // The font family a plain terminal's command (its third line) is drawn
  // in, such as the terminal's own font; absent, the row's font.
  commandFont?: string;
}

// A finished terminal's row content, one line: a "✓" in the done color
// where a live row has its program icon, or a "✗" in the blocked color when
// it failed (`finishedOutcome`), then its label (`finishedLabel`) muted, and
// at the end, dim, `opts.parentHint` ("↳ lead") and `opts.hint` as on a
// `terminalRow`, how it ended ("exit 1") and how long ago (none when the
// core gave no time). `now` is the time in ms since the epoch. `t` is the
// theme's colors by name (`theme()`). Like `terminalRow`'s, the content
// keeps 6px above and below. Without `opts`, it shows no hints.
export function finishedRow(
  t: Record<string, Color>,
  f: FinishedTerminal,
  now: number,
  opts: Pick<TerminalRowOptions, "hint" | "parentHint"> = {},
): Element {
  const outcome = finishedOutcome(f);
  const label = finishedLabel(f);
  const ended = f.finishedMs > 0 ? duration(now - f.finishedMs) : null;
  const dimText = (text: string) =>
    div().flex_none().text_size(11).text_color(t.dim).child(text);

  const mark = div()
    .size(ICON_SIZE)
    .flex_none()
    .mt(2)
    .mr(8)
    .flex()
    .items_center()
    .justify_center()
    .text_size(11.5)
    .font_bold()
    .text_color(outcome.failed ? t.blocked : (t.done ?? t.dim))
    .child(outcome.failed ? "✗" : "✓");
  const line = h_flex()
    .min_w(0)
    .gap(6)
    .items_center()
    .child(
      div()
        .id(`finished-label-${f.address}`)
        .flex_1()
        .min_w(0)
        .truncate()
        .text_color(t.muted)
        .tooltip(label)
        .child(label),
    )
    .when(Boolean(opts.parentHint), (el) =>
      el.child(dimText(`↳ ${opts.parentHint}`)),
    )
    .when(Boolean(opts.hint), (el) => el.child(dimText(opts.hint ?? "")))
    .child(dimText(outcome.text))
    .when(ended !== null, (el) => el.child(dimText(ended ?? "")));

  return h_flex()
    .flex_1()
    .min_w(0)
    .py(ROW_PAD_Y)
    .items_start()
    .text_size(12.5)
    .child(mark)
    .child(v_flex().flex_1().min_w(0).line_height(1.3).child(line));
}

// The side of a row's square program icon, in px.
const ICON_SIZE = 14;
// The space above and below a terminal row's content, in px.
const ROW_PAD_Y = 6;
