// The title bar of a popup terminal: a modal dialog overlay whose layout
// holds this block above a `{ terminal }` block, opened by the launcher mods
// (`find`, `jj-workspace-new`, `jj-workspace-pick`, `jj-workspace-remove`,
// `space-new`) for an interactive CLI running in a core terminal. The overlay
// closes by itself when that terminal's program ends.
//
// Props:
// - `overlay`: this popup's overlay id, filled in by the host.
// - `title`: the text shown in the bar, and the title of its error toasts.
// - `terminal`: the address of the terminal shown below the bar.
// - `keepTerminal` (optional): true leaves the terminal running when the
//   popup closes, for a long-lived terminal shown again by a later popup.
//   Absent or false, this block owns the terminal's lifetime: when the
//   overlay closes any other way than its program ending (its ✕, a layout
//   switch, quit), `close()` kills it, so no popup terminal outlives its
//   popup.
// - `openCommand` (optional, `{ command, args }`): run once through `exec`
//   when the popup opens. When it exits nonzero or cannot start, the popup
//   posts an error toast with its stderr and closes itself.
// - `closeCommand` (optional, `{ command, args }`): run through `exec` when
//   the popup closes, by any route; its result is ignored.
// In either command's `args`, an element exactly equal to `{overlay}` is
// replaced with this popup's overlay id.

import { View, div } from "gpui-kit";
import { h_flex } from "gpui-base";
import {
  closeOverlay,
  exec,
  notify,
  props,
  run,
  terminals,
  theme,
} from "herdr";

const OVERLAY_PLACEHOLDER = "{overlay}";

// Runs a `{ command, args }` prop through `exec`, with the overlay
// placeholder in ARGS replaced by OVERLAY.
function execCommand({ command, args = [] }, overlay) {
  return exec(
    command,
    args.map((arg) => (arg === OVERLAY_PLACEHOLDER ? overlay : arg)),
  );
}

export default class Popup extends View {
  init(_props, cx) {
    // `herdr-app check` renders the mod with no props, outside an overlay.
    // Start nothing then.
    const { overlay, title, openCommand } = props() ?? {};
    if (!overlay || !openCommand) return;

    cx.spawn(async (_cx) => {
      let body;
      try {
        const r = await execCommand(openCommand, overlay);
        if (r.code === 0) return;
        body =
          r.stderr.trim() || `${openCommand.command} exited with ${r.code}`;
      } catch (error) {
        body = String(error?.message ?? error);
      }
      notify({ title: title ?? "Popup", body, level: "error" });
      closeOverlay(overlay);
    });
  }

  render(_cx) {
    const t = theme();
    const { title, overlay } = props() ?? {};
    return h_flex()
      .size_full()
      .px(12)
      .gap(8)
      .items_center()
      .bg(t.surface)
      .border_b(1)
      .border_color(t.border)
      .text_size(12)
      .child(
        div()
          .flex_1()
          .truncate()
          .font_semibold()
          .text_color(t.foreground)
          .child(title ?? ""),
      )
      .child(
        div()
          .id("popup-close")
          .px(8)
          .py(2)
          .rounded(5)
          .text_color(t.muted)
          .cursor_pointer()
          .hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click(() => {
            if (overlay) closeOverlay(overlay);
          })
          .child("✕"),
      );
  }

  // Runs once when the overlay goes, by any route. On quit only `exec` and
  // `terminal.kill` still go out (an `hc` call would be lost), so the close
  // command uses `exec` and the kill is a synchronous `run`. The kill skips
  // a terminal that is no longer listed: one that ended normally is already
  // gone, and killing it would show an error toast. A close within
  // milliseconds of opening, before the terminal is listed, therefore leaves
  // it running; that is accepted.
  async close(_cx) {
    const { overlay, terminal, keepTerminal, closeCommand } = props() ?? {};
    const closing = closeCommand
      ? execCommand(closeCommand, overlay).catch(() => {})
      : undefined;
    if (
      terminal &&
      keepTerminal !== true &&
      terminals().some((t) => t.address === terminal)
    ) {
      run("terminal.kill", { terminal });
    }
    await closing;
  }
}
