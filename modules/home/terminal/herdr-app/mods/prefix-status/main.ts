// Started as a copy of the Herdr app's shipped `workspace-status` status bar
// (herdr-app 0.1.11). It changes two things. While prefix mode is on, the bar
// shows an accent "PREFIX" pill and the prefix key hints the `prefix` mod
// publishes as `shared("prefix").hints` (`[key, label]` pairs). And its
// palette chip opens, and its key hint shows the key of, the personal
// `palette` mod (the command palette copy with ctrl-j/ctrl-k) instead of the
// built-in palette. Otherwise it draws the bar as 0.1.11 shipped it.
import { View, div, svg } from "gpui-kit";
import type { AsyncContext, Color } from "gpui-kit";
import type { Props } from "gpui-shell";
import { h_flex } from "gpui-base";
import {
  spaces,
  agents,
  theme,
  run,
  window,
  keys,
  shared,
  nextCommand,
} from "herdr";

// The theme's colors by name. The app's typings type `theme()` as
// `Record<string, string>`, though every value is a color.
type ThemeColors = Record<string, Color>;

// What the `prefix` mod publishes as `shared("prefix")`: its key hints as
// `[key, label]` pairs, in the order the bar shows them.
interface PrefixShared {
  hints?: [string, string][];
}

export default class WorkspaceStatus extends View {
  // Whether prefix mode is on, so the bar shows the PREFIX pill and hints.
  declare prefix: boolean;

  // Prefix mode is on between the `prefix` mod's "prefix-status.on" and
  // ".off" commands; a command, unlike setShared, reliably redraws the bar.
  init(_props: Props | undefined, cx: AsyncContext): void {
    this.prefix = false;
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        this.prefix = c === "on";
        cx.notify();
      }
    });
  }

  // The `palette` mod's key as actually bound, not a hardcoded one; without a
  // binding the hint stays useful ("commands") instead of lying.
  hint(t: ThemeColors): string {
    const mac = window()?.platform === "macos";
    const mod: Record<string, string> = {
      cmd: mac ? "⌘" : "Ctrl+",
      ctrl: mac ? "⌃" : "Ctrl+",
      shift: mac ? "⇧" : "Shift+",
      alt: mac ? "⌥" : "Alt+",
      option: mac ? "⌥" : "Alt+",
    };
    const b = keys().find(
      (k) => k.section === "global" && k.action === "mod.open:palette",
    );
    const parts =
      b && b.keys.endsWith("--")
        ? [...b.keys.slice(0, -2).split("-"), "-"]
        : b?.keys.split("-");
    const key =
      parts &&
      parts.map((p) => mod[p.toLowerCase()] ?? p.toUpperCase()).join("");
    return key ? `${key}  commands` : "commands";
  }

  render() {
    const t = theme() as ThemeColors;
    const space = spaces().find((s) => s.active);
    const list = agents();
    const needs = list.filter((a) => a.status === "blocked").length;
    // Prefix mode (the `prefix` mod): the bar turns into tmux-style key hints.
    if (this.prefix) {
      const hint = (k: string, what: string) =>
        h_flex()
          .gap(5)
          .items_center()
          .child(div().text_color(t.foreground).font_semibold().child(k))
          .child(div().text_color(t.muted).child(what));
      return h_flex()
        .size_full()
        .px(14)
        .gap(14)
        .items_center()
        .bg(t.chrome)
        .border_t(1)
        .border_color(t.accent)
        .text_size(11.8)
        .child(
          div()
            .px(7)
            .rounded(4)
            .bg(t.accent)
            .text_color(t.solid_foreground)
            .font_semibold()
            .child("PREFIX"),
        )
        .children(
          ((shared("prefix") as PrefixShared)?.hints ?? []).map(([k, what]) =>
            hint(k, what),
          ),
        );
    }
    const label = (icon: string, text: string) =>
      h_flex()
        .gap(6)
        .items_center()
        .child(svg(`mods/workspace-chrome/${icon}.svg`).size(13))
        .child(text);
    return h_flex()
      .size_full()
      .px(14)
      .gap(16)
      .items_center()
      .bg(t.chrome)
      .border_t(1)
      .border_color(t.border)
      .text_size(11.8)
      .text_color(t.muted)
      .child(
        label(
          space?.machine ? "server" : "monitor",
          space?.machine ?? "This computer",
        ),
      )
      .when(Boolean(space?.branch), (el) =>
        el.child(label("branch", space.branch)),
      )
      .child(
        h_flex()
          .gap(6)
          .items_center()
          .child(div().size(6).rounded(3).bg(t.dim))
          .child(`${list.length} agents`)
          .when(needs > 0, (el) =>
            el.child(div().text_color(t.blocked).child(`· ${needs} needs you`)),
          ),
      )
      .child(div().flex_1())
      .child(
        div()
          .id("palette")
          .text_color(t.dim)
          .on_click(() => run("mod.open", { name: "palette" }))
          .child(this.hint(t)),
      );
  }
}
