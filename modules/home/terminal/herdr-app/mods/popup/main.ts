// The title bar of a popup terminal: a modal dialog overlay whose layout
// holds this block above a `{ terminal }` block, opened by the launcher mods
// (`jj-workspace-pick`, `jj-workspace-remove`, `space-new`) for an
// interactive CLI running in a core terminal. The overlay closes by itself
// when that terminal's program ends.
//
// Props:
// - `overlay`: this popup's overlay id, filled in by the host.
// - `title`: the text shown in the bar.
// - `terminal`: the address of the terminal shown below the bar.
//
// This block owns the terminal's lifetime: when the overlay closes any other
// way than its program ending (its ✕, a layout switch, quit), `close()` kills
// it, so no popup terminal outlives its popup.

import { View, div } from "gpui-kit";
import type { AsyncContext, Color, Context } from "gpui-kit";
import { h_flex } from "gpui-base";
import { closeOverlay, props, run, terminals, theme } from "herdr";

// The theme's colors by name. The app's typings type `theme()` as
// `Record<string, string>`, though every value is a color.
type ThemeColors = Record<string, Color>;

// This block's props, as the header describes them. All are absent when
// `herdr-app check` renders the mod.
interface PopupProps {
  overlay?: string;
  title?: string;
  terminal?: string;
}

export default class Popup extends View {
  render(_cx: Context) {
    const t = theme() as ThemeColors;
    const { title, overlay }: PopupProps = props() ?? {};
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

  // Runs once when the overlay goes, by any route. On quit only
  // `terminal.kill` still goes out (an `hc` call would be lost), so the kill
  // is a synchronous `run`. The kill skips a terminal that is no longer
  // listed: one that ended normally is already gone, and killing it would
  // show an error toast. A close within milliseconds of opening, before the
  // terminal is listed, therefore leaves it running; that is accepted.
  close(_cx: AsyncContext): void {
    const { terminal }: PopupProps = props() ?? {};
    if (terminal && terminals().some((t) => t.address === terminal)) {
      run("terminal.kill", { terminal });
    }
  }
}
