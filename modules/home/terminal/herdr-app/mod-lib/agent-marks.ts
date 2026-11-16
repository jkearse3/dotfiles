// How an agent row draws its status (`statusMark`) and the time since that
// status changed (`duration`), as the desk-spaces sidebar's agent rows do.
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/agent-marks.ts` -> `../../mod-lib/agent-marks.ts`), and the
// herdr-app-mods build copies the file in place of the link and strips its
// types to `agent-marks.js`. The app refuses imports that leave a mod's own
// folder; `./agent-marks.js` beside the importing file is allowed. It imports
// `./status.js`, so a mod linking it links `status.ts` too.

import { div, svg } from "gpui-kit";
import type { Color, Element } from "gpui-kit";
import type { AgentStatus } from "./status.js";

// An agent status as the shipped agents list draws it in priority view: a
// spinner for working, a "!" for blocked, a dot for done, a ring for idle,
// and an invisible dot of the same size for any other status or none, so
// rows stay aligned. `t` is the theme's colors by name (`theme()`).
export function statusMark(
  t: Record<string, Color>,
  status: AgentStatus | null,
): Element {
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

// `ms` as the agents list writes how long ago something happened: "<1m"
// under a minute, then whole minutes ("5m"), hours ("3h") or days ("2d"),
// rounded down. Copied from the shipped `agents` mod.
export function duration(ms: number): string {
  const m = Math.floor(ms / 60000);
  if (m < 1) return "<1m";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}
