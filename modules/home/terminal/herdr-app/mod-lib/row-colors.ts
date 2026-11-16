// The colors a row draws itself with beyond the theme's own: a hovered row's
// fill (`hoverFill`), mixed from the backdrop the row sits on and the theme's
// `hover` color, and the stripe on a terminal row's left edge that shows its
// state (`stripeColor`).
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/row-colors.ts` -> `../../mod-lib/row-colors.ts`), and the
// herdr-app-mods build copies the file in place of the link and strips its
// types to `row-colors.js`. The app refuses imports that leave a mod's own
// folder; `./row-colors.js` beside the importing file is allowed. It imports
// only types, so it needs no other file beside it.

import type { Color } from "gpui-kit";
import type { TerminalRowModel } from "./labels.js";

// A hovered row's fill: halfway from `backdrop`, the color the row sits on,
// to the focused row's `t.hover`, so a hovered row next to the focused one
// reads as a lighter touch, not a second selection. `t.hover` itself when
// either color isn't hex ("#rgb", "#rrggbb" or "#rrggbbaa"); alpha mixes
// like the other channels, a color without one counting as opaque.
export function hoverFill(t: Record<string, Color>, backdrop: Color): Color {
  const a = channels(backdrop);
  const b = channels(t.hover);
  if (!a || !b) return t.hover;
  const mix = a.map((v, i) => Math.round((v + b[i]) / 2));
  return `#${mix.map((v) => v.toString(16).padStart(2, "0")).join("")}`;
}

// A hex color "#rgb", "#rrggbb" or "#rrggbbaa" as [r, g, b, a], or null.
function channels(hex: string | undefined): number[] | null {
  const m = /^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.exec(hex ?? "");
  if (!m) return null;
  const h = m[1].length === 3 ? [...m[1]].map((c) => c + c).join("") : m[1];
  return [0, 2, 4, 6].map((i) =>
    i < h.length ? parseInt(h.slice(i, i + 2), 16) : 255,
  );
}

// The color of the stripe on a terminal row's left edge, which tells the
// terminal's state at a glance: an agent's status (`model.status`) in the
// colors `statusMark` draws it with, working `t.working`, blocked
// `t.blocked`, done `t.done` (`t.dim` without one), and idle or any other
// word, such as a sub-agent's raw status, `t.idle` (`t.dim` without one); a
// plain terminal running a command (`model.detail` of kind "command") cyan
// `t.ansi6`, and any other plain terminal the idle agent's grey. A sub-agent
// that is done gets the idle grey: the sidebar shows it idle (`rowStatus`).
export function stripeColor(
  t: Record<string, Color>,
  model: Pick<TerminalRowModel, "status" | "detail">,
): Color {
  if (model.status === null && model.detail?.kind === "command") return t.ansi6;
  if (model.status === "working") return t.working;
  if (model.status === "blocked") return t.blocked;
  if (model.status === "done") return t.done ?? t.dim;
  return t.idle ?? t.dim;
}
