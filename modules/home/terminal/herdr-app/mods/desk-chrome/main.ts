// The sidebar's header and footer in the `desk` layout. Started as a copy of
// the app's shipped `workspace-chrome` mod (herdr-app 0.1.11), with its asset
// paths pointing at its own folder and its search button opening the `find`
// mod (the find hub) instead of the built-in picker.
//
// The wide header also holds the machine picker (`machinePicker`): while
// the `desk-spaces` sidebar knows a machine other than this computer, a
// "Choose machines" button left of the search button reads "<shown> of
// <known>" and opens a picker below it. The picker has a checkbox per
// machine the sidebar gives a header, with the state badge that header
// shows, this computer's checked and disabled; then "Hide offline
// machines"; then a note that blocked agents on hidden machines still show
// in "Needs you". Toggling a box saves the choice in `shared`
// (`machine-choices.ts`, a link to the shared copy in `mod-lib/`), which the
// sidebar applies, and the picker stays open. A click outside it or Esc
// closes it.

import { View, div, image, svg } from "gpui-kit";
import type { ClickEvent, Color, Context, Element } from "gpui-kit";
import { Checkbox, Popover, h_flex, v_flex } from "gpui-base";
import {
  theme,
  run,
  props,
  window,
  shared,
  setShared,
  updates,
  layout,
} from "herdr";
import type { Props } from "gpui-shell";
import {
  HIDDEN_MACHINES_KEY,
  HIDE_OFFLINE_MACHINES_KEY,
  MACHINE_PICKER_KEY,
  machineLeftOut,
  readMachineChoices,
  readMachinePicker,
} from "./machine-choices.js";

// The theme's colors by name. The app's typings type `theme()` as
// `Record<string, string>`, though every value is a color.
type ThemeColors = Record<string, Color>;

// The fields of a `layout()` block this mod reads. The app's typings type
// `layout()` as `unknown`.
interface LayoutNode {
  id?: string;
  size?: { px?: number };
  children?: LayoutNode[];
}

function find(
  node: LayoutNode | null | undefined,
  id: string,
): LayoutNode | null {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The sidebar's rail goes by its width, not a flag: dragging its edge narrows it too.
const narrow = () =>
  (find(layout() as LayoutNode, "sidebar")?.size?.px ?? Infinity) < 160;

// To the rail (on macOS wide enough for the traffic lights), or back to the width it had.
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

export default class WorkspaceChrome extends View {
  // Whether the machine picker is open.
  declare pickerOpen: boolean;

  init(_props: Props | undefined): void {
    this.pickerOpen = false;
  }

  button(
    id: string,
    label: Element,
    action: (event: ClickEvent, cx: Context) => void,
  ): Element {
    const t = theme() as ThemeColors;
    return div()
      .id(id)
      .size(26)
      .flex_none()
      .flex()
      .items_center()
      .justify_center()
      .rounded(6)
      .text_color(t.muted)
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_click(action)
      .child(label);
  }

  // The "Choose machines" button and its picker, as the header comment
  // describes; none while the sidebar knows no machine but this computer.
  machinePicker(t: ThemeColors): Element[] {
    const known = readMachinePicker(shared(MACHINE_PICKER_KEY));
    if (!known.some((m) => m.name !== null)) {
      // So the picker does not reopen by itself when the button comes back.
      this.pickerOpen = false;
      return [];
    }

    const choices = readMachineChoices(
      shared(HIDDEN_MACHINES_KEY),
      shared(HIDE_OFFLINE_MACHINES_KEY),
    );
    const shown = known.filter((m) => machineLeftOut(m, choices) === null);
    const setHidden = (name: string, hidden: boolean) => {
      const names = new Set(choices.hidden);
      if (hidden) names.add(name);
      else names.delete(name);
      setShared(HIDDEN_MACHINES_KEY, [...names]);
    };
    const trigger = h_flex()
      .id("machine-picker-button")
      .h(26)
      .px(7)
      .gap(6)
      .flex_none()
      .items_center()
      .rounded(6)
      .text_size(12)
      .text_color(t.muted)
      .cursor_pointer()
      .accessibility_label("Choose machines")
      .tooltip("Choose machines")
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .when(this.pickerOpen, (el) => el.bg(t.hover))
      .child(svg("mods/desk-chrome/server.svg").size(13))
      .child(`${shown.length} of ${known.length}`);
    const panel = v_flex()
      .w(250)
      .p(6)
      .gap(2)
      .rounded(8)
      .border(1)
      .border_color(t.border)
      .bg(t.popover)
      .text_size(12.5)
      .text_color(t.foreground)
      // A press in the picker neither drags the window nor reaches the
      // header under it.
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .children(
        known.map((m) =>
          checkRow(
            `machine-pick-${m.name ?? "local"}`,
            m.label,
            m.badge,
            m.name === null || !choices.hidden.has(m.name),
            m.name === null,
            t,
            (checked) => {
              if (m.name !== null) setHidden(m.name, !checked);
            },
          ),
        ),
      )
      .child(div().h(1).my(4).bg(t.border))
      .child(
        checkRow(
          "machine-pick-hide-offline",
          "Hide offline machines",
          null,
          choices.hideOffline,
          false,
          t,
          (checked) => setShared(HIDE_OFFLINE_MACHINES_KEY, checked),
        ),
      )
      .child(
        div()
          .px(6)
          .pt(4)
          .pb(2)
          .text_size(11.5)
          .text_color(t.dim)
          .child("Blocked agents on hidden machines still show in Needs you."),
      );
    // The wrapper stops the press that opens the picker from also dragging
    // the window, as `button` does.
    return [
      div()
        .flex_none()
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .child(
          Popover.new("machine-picker")
            .anchor("top_left")
            .open(this.pickerOpen)
            .on_open_change((open, cx) => {
              this.pickerOpen = open;
              cx.notify();
            })
            .trigger(trigger)
            .content(panel),
        ),
    ];
  }

  render() {
    const t = theme() as ThemeColors;
    const collapsed = narrow();
    if (props()?.footer) {
      const row = (
        id: string,
        icon: string,
        label: string,
        dim: boolean,
        action: () => void,
      ) =>
        h_flex()
          .id(id)
          .h(28)
          .px(8)
          .gap(9)
          .items_center()
          .rounded(8)
          .text_color(dim ? t.dim : t.muted)
          .hover((s) => s.bg(t.hover).text_color(t.foreground))
          .cursor_pointer()
          .on_click(action)
          .child(svg(`mods/desk-chrome/${icon}.svg`).size(14))
          .when(!collapsed, (el) => el.child(label));
      return v_flex()
        .size_full()
        .bg(t.chrome)
        .border_t(1)
        .border_color(t.border)
        .px(8)
        .pt(4)
        .pb(8)
        .text_size(13)
        .child(
          row("settings", "settings", "Settings", false, () =>
            run("app.settings"),
          ).when(Boolean(updates().app.ready), (el) =>
            el.child(div().size(6).rounded_full().bg(t.accent)),
          ),
        )
        .child(
          row("machine", "plus", "Add machine", true, () =>
            run("mod.open", { name: "machine-add" }),
          ),
        );
    }
    return (
      h_flex()
        .size_full()
        .bg(t.chrome)
        .pl(collapsed ? 6 : 14)
        .pr(10)
        .gap(4)
        .items_center()
        .text_size(13.5)
        .when(window()?.platform === "macos" && !collapsed, (el) => el.pl(76))
        .when(!collapsed, (el) =>
          el.child(
            h_flex()
              .flex_1()
              .gap(8)
              .items_center()
              .child(image("frame/welcome/herdr.png").size(20).rounded(5))
              .child(
                div().font_semibold().text_color(t.foreground).child("Herdr"),
              ),
          ),
        )
        .when(!collapsed, (el) => el.children(this.machinePicker(t)))
        .when(!collapsed, (el) =>
          el.child(
            this.button(
              "search",
              svg("mods/desk-chrome/search.svg").size(15),
              () => run("mod.open", { name: "find" }),
            ),
          ),
        )
        // On the macOS rail the traffic lights fill the row; the spaces list's » unfolds it.
        .when(!(collapsed && window()?.platform === "macos"), (el) =>
          el.child(
            this.button(
              "sidebar-toggle",
              svg("mods/desk-chrome/sidebar.svg").size(15),
              toggleSidebar,
            ),
          ),
        )
    );
  }
}

// One checkbox line of the machine picker: a box, checked or not, then
// `label`, then `badge` when there is one. A `disabled` line shows dimmed and
// ignores presses; any other calls `onToggle` with the new checked state.
function checkRow(
  id: string,
  label: string,
  badge: string | null,
  checked: boolean,
  disabled: boolean,
  t: ThemeColors,
  onToggle: (checked: boolean) => void,
): Element {
  const box = div()
    .size(14)
    .flex_none()
    .flex()
    .items_center()
    .justify_center()
    .rounded(4)
    .border(1)
    .border_color(checked ? t.accent : t.input)
    .when(checked, (el) =>
      el
        .bg(t.accent)
        .text_color(t.accent_foreground)
        .child(svg("mods/desk-chrome/check.svg").size(10)),
    );
  return Checkbox.new(id)
    .checked(checked)
    .disabled(disabled)
    .on_change((value, cx) => {
      onToggle(value);
      cx.notify();
    })
    .flex()
    .items_center()
    .gap(8)
    .h(28)
    .px(6)
    .rounded(6)
    .when(disabled, (el) => el.opacity(0.6))
    .when(!disabled, (el) => el.cursor_pointer().hover((s) => s.bg(t.hover)))
    .child(box)
    .child(div().flex_1().min_w(0).truncate().child(label))
    .when(badge !== null, (el) =>
      el.child(
        div()
          .flex_none()
          .px(5)
          .rounded(4)
          .bg((t.dim + "26") as Color)
          .text_size(10.5)
          .text_color(t.dim)
          .child(badge ?? ""),
      ),
    );
}
