// Renames every space at once (`ctrl-b ctrl-w`), in a dialog styled like the
// app's rename prompt: one row per space, with its colored avatar, the
// checkout its first terminal is in ("dotfiles / ws3", a machine's spaces
// after that machine's name), and a field holding its name. Tab, down or
// ctrl-j moves to the next field, Shift-Tab, up or ctrl-k to the previous;
// Enter or Save renames each space whose name changed, and Esc or Cancel
// renames nothing. An emptied field gives that space back its automatic
// name, after where its first terminal is.
// `ctrl-b shift-w` renames only the shown space.
//
// `paths.js` beside this file is a link to the shared copy in `mod-lib/`.

import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import {
  closeOverlay,
  exec,
  home,
  panes,
  props,
  run,
  settings,
  shared,
  spaces,
  theme,
} from "herdr";
import { cliPath, place } from "./paths.js";

export default class SpaceRenameAll extends View {
  init(_props, cx) {
    const ps = panes();
    // One row per space as the dialog opened: `initial` is the name a field
    // starts with, empty for a space nobody named; `automatic` the name an
    // empty field saves to, shown greyed in it (a renamed space's is worked
    // out, so null until known, see `automaticName`); `checkout` its first
    // terminal's checkout once known (see `checkout`); and `focused` whether
    // its field holds the keyboard now. `this.current` stays on the last
    // focused row after the keyboard leaves it, so Tab still moves from there.
    this.rows = spaces().map((space, i) => {
      const initial = space.named ? space.name : "";
      // The field's own placeholder is fixed at creation, before a renamed
      // space's automatic name is known, so `render` draws the hint instead.
      const input = InputState.new({ value: initial });
      input.on("change", (_e, cx) => cx.notify());
      input.on("focus", (_e, cx) => {
        this.current = i;
        this.rows[i].focused = true;
        this.reveal(this.rows[i]);
        cx.notify();
      });
      input.on("blur", (_e, cx) => {
        this.rows[i].focused = false;
        cx.notify();
      });
      input.on("submit", () => this.apply());
      return {
        id: space.id,
        initial,
        input,
        machine: space.machine,
        path: place(space, ps),
        automatic: space.named ? null : space.name,
        checkout: null,
        focused: false,
      };
    });

    // The shown space's field takes the keyboard, its name selected, as in
    // the app's prompt. The frame may take the keyboard back while it loads,
    // so the field asks again once the frame has settled, but only while no
    // other row has taken the keyboard and the opening row's space still
    // exists, so an early Tab or click is never undone.
    this.scroll = 0;
    this.current = Math.max(
      0,
      spaces().findIndex((s) => s.active),
    );
    const opening = this.rows[this.current];
    if (opening) {
      this.reveal(opening);
      const length = opening.input.value().length;
      if (length) opening.input.set_selected_range({ start: 0, end: length });
      opening.input.focus();
      cx.timer.after(600, () => {
        if (
          this.rows[this.current] === opening &&
          this.live().includes(opening)
        )
          opening.input.focus();
      });
    }
    this.handle = cx.focus_handle();

    for (const row of this.rows) {
      if (row.automatic === null)
        cx.spawn(async (cx) => {
          row.automatic = await automaticName(row.path, row.machine);
          cx.notify();
        });
      if (!row.path) continue;
      cx.spawn(async (cx) => {
        row.checkout = await checkout(row.path, row.machine);
        cx.notify();
      });
    }
  }

  // The rows whose space still exists, in the dialog's order.
  live() {
    const ids = new Set(spaces().map((s) => s.id));
    return this.rows.filter((r) => ids.has(r.id));
  }

  // Scrolls the list just far enough to show ROW whole. Focus moving to a row
  // calls this, so moving between fields never leaves the field taking keys
  // out of sight.
  reveal(row) {
    const top = this.live().indexOf(row) * ROW_PITCH;
    if (top < 0) return;
    const visible = this.shownHeight(this.live().length);
    if (top < this.scroll) this.scroll = top;
    if (top + ROW_H > this.scroll + visible)
      this.scroll = top + ROW_H - visible;
  }

  // How much of the list the dialog shows for COUNT rows: all of them up to
  // ROWS_MAX_H, less when the window is too short for the dialog to hold that
  // and layout squeezes the list (`rowsLaidOutHeight`, measured after each
  // layout, unknown before the first frame).
  shownHeight(count) {
    return Math.min(
      ROWS_MAX_H,
      rowsHeight(count),
      this.rowsLaidOutHeight ?? Infinity,
    );
  }

  // Moves the keyboard off the focused row once its space has closed: to the
  // next surviving row, else the last one, else the dialog itself, so Tab,
  // Enter and Esc keep working. Focusing is refused during render, so it
  // happens on the next turn; `rehoming` keeps renders before then from
  // queueing it again.
  rehome(cx) {
    if (this.rehoming) return;
    this.rehoming = true;
    cx.timer.after(0, () => {
      this.rehoming = false;
      const shown = this.live();
      if (shown.includes(this.rows[this.current])) return;
      const next =
        shown.find((r) => this.rows.indexOf(r) > this.current) ?? shown.at(-1);
      this.current = next ? this.rows.indexOf(next) : -1;
      (next?.input ?? this.handle).focus();
    });
  }

  // Closes the dialog, then renames each remaining space whose field
  // changed; an emptied field restores the automatic name.
  apply() {
    const changed = this.live().filter(
      (r) => r.input.value().trim() !== r.initial,
    );
    closeOverlay(props().overlay);
    for (const r of changed)
      run("space.rename", { id: r.id, name: r.input.value().trim() });
  }

  key(e, cx) {
    const k = e.key;
    // fzf's ctrl-j/ctrl-k, as in the palette: control alone, so cmd/alt/shift
    // chords pass.
    const m = e.modifiers;
    const isControlOnly = m.control && !m.platform && !m.alt && !m.shift;
    const isDown =
      (k === "tab" && !m.shift) || k === "down" || (k === "j" && isControlOnly);
    const isUp =
      (k === "tab" && m.shift) || k === "up" || (k === "k" && isControlOnly);
    if (k === "escape") closeOverlay(props().overlay);
    else if (isDown || isUp) {
      const shown = this.live();
      if (shown.length) {
        const at = shown.indexOf(this.rows[this.current]);
        const step = isUp ? -1 : 1;
        const next = at < 0 ? 0 : (at + step + shown.length) % shown.length;
        shown[next].input.focus();
      }
    } else return;
    cx.stop_propagation();
  }

  render(cx) {
    const t = theme();
    const shown = this.live();
    if (this.current >= 0 && !shown.includes(this.rows[this.current]))
      this.rehome(cx);

    // All rows stay mounted, so a field holding the keyboard never leaves the
    // tree; the list scrolls by sliding them inside a clipped window.
    // The list asks for its full height; what it shows (`visible`) may be less.
    const total = rowsHeight(shown.length);
    const height = Math.min(ROWS_MAX_H, total);
    const visible = this.shownHeight(shown.length);
    const maxScroll = total - visible;
    this.scroll = Math.max(0, Math.min(this.scroll, maxScroll));
    const colors = shared("space.colors") ?? {};
    const byId = new Map(spaces().map((s) => [s.id, s]));
    const button = (id, text, primary, action) =>
      h_flex()
        .id(id)
        .h(32)
        .px(14)
        .items_center()
        .rounded(8)
        .border_1()
        .border_color(primary ? t.solid : t.input)
        .bg(primary ? t.solid : t.raised)
        .text_color(primary ? t.solid_foreground : t.foreground)
        .text_size(12.5)
        .font_medium()
        .cursor_pointer()
        .hover((s) => s.opacity(0.88))
        .on_click(action)
        .child(text);
    const row = (r) => {
      const space = byId.get(r.id);
      const color = colors[r.id] ?? "ansi6";
      const fill = color.startsWith("#") ? color : (MARK[color] ?? t[color]);
      return h_flex()
        .id(`row-${r.id}`)
        .h(ROW_H)
        .flex_none()
        .gap(10)
        .items_center()
        .child(
          h_flex()
            .size(18)
            .flex_none()
            .rounded(5)
            .bg(fill)
            .items_center()
            .justify_center()
            .text_size(10.5)
            .font_bold()
            .text_color("#ffffff")
            .child([...space.name][0]?.toUpperCase() ?? "?"),
        )
        .child(
          div()
            .w(170)
            .flex_none()
            .min_w(0)
            .truncate()
            .text_size(11.5)
            .text_color(t.dim)
            .child(checkoutLabel(space, r)),
        )
        .child(
          div()
            .relative()
            .flex_1()
            .min_w(0)
            .child(
              Input.new(r.input)
                .w_full()
                .h(ROW_H)
                .px(10)
                .rounded(8)
                .border_1()
                .border_color(r.focused ? t.accent : t.input)
                .bg(t.background)
                .text_size(12.8)
                .text_color(t.foreground),
            )
            // An empty field's hint: the name saving it gives the space. It
            // sits over the field without handlers, so clicks reach the field.
            .when(Boolean(r.automatic) && r.input.value() === "", (el) =>
              el.child(
                h_flex()
                  .absolute()
                  .top(0)
                  .left(11)
                  .right(11)
                  .h(ROW_H)
                  .items_center()
                  .text_size(12.8)
                  .text_color(t.dim)
                  .child(div().min_w(0).truncate().child(r.automatic)),
              ),
            ),
        );
    };
    return v_flex()
      .id("space-rename-all")
      .track_focus(this.handle)
      .on_key_down((e, cx) => this.key(e, cx))
      .w_full()
      .min_h(0)
      .p(18)
      .bg(t.popover)
      .text_color(t.foreground)
      .child(
        h_flex()
          .items_center()
          .child(
            div().flex_1().text_size(15).font_semibold().child("Rename spaces"),
          )
          .child(div().text_size(11).text_color(t.dim).child("Esc")),
      )
      .child(
        div()
          .pt(6)
          .text_size(11.5)
          .text_color(t.dim)
          .child("Empty: named after its folder · Tab or ctrl-j/k: move"),
      )
      .child(
        div()
          .id("rows")
          .mt(14)
          .h(height)
          .overflow_hidden()
          // A short window caps the dialog's height, and the list gives up the
          // difference; the scroll range and `reveal` follow what it kept.
          .on_size_change((size, cx) => {
            this.rowsLaidOutHeight = size.height / settings().zoom;
            if (this.current >= 0) this.reveal(this.rows[this.current]);
            cx.notify();
          })
          .on_scroll_wheel((e, cx) => {
            this.scroll = Math.max(
              0,
              Math.min(this.scroll - e.delta.y, maxScroll),
            );
            cx.stop_propagation();
            cx.notify();
          })
          .child(
            v_flex()
              .relative()
              .top(-this.scroll)
              .gap(ROW_GAP)
              .children(shown.map(row)),
          ),
      )
      .child(
        h_flex()
          .pt(20)
          .gap(8)
          .justify_end()
          .child(
            button("rename-cancel", "Cancel", false, () =>
              closeOverlay(props().overlay),
            ),
          )
          .child(button("rename-save", "Save", true, () => this.apply())),
      );
  }
}

// A row's height, the space between rows, and the tallest the list grows
// before it scrolls.
const ROW_H = 32;
const ROW_GAP = 8;
const ROWS_MAX_H = 420;
const ROW_PITCH = ROW_H + ROW_GAP;

// The height COUNT rows take stacked, gaps between them.
const rowsHeight = (count) => Math.max(0, count * ROW_PITCH - ROW_GAP);

// What desk-spaces' checkout line says for SPACE, on every row here:
// "dotfiles / ws3" for a checkout whose folder differs from its repo's name,
// "dotfiles" when they match, and the folder alone outside a repo ("~" at
// its machine's home). Another machine's space starts with that machine's
// name. `row.path` is where its first terminal is, else the folder the space
// was made in (empty for a new space on another machine until its terminal
// reports one); `row.checkout` its checkout, null until known or outside a
// repo.
function checkoutLabel(space, row) {
  const c = row.checkout;
  const path = c?.top ?? row.path;
  const folder =
    !path || (!space.machine && path === home()) ? "~" : base(path);
  const same = (a, b) => a.toLowerCase() === b.toLowerCase();
  const text = !c || same(c.name, folder) ? folder : `${c.name} / ${folder}`;
  return space.machine ? `${space.machine} · ${text}` : text;
}

// The name the app gives a space whose first terminal is in CWD, on machine
// ON (null: this one), when the space has no name of its own: after the Git
// checkout CWD is in when git names both its root and its HEAD, else CWD
// itself (outside a repo, and in a repo with no commits yet); "~" at its
// machine's home. Mirrors the app's automatic space name (its model.rs
// `space_name`), which reads the folder from window.rs `folder_info`: the
// same git command, run only away from this machine's home.
async function automaticName(cwd, on) {
  let top = cwd;
  if (cwd && (on || cwd !== home()))
    try {
      const git = await exec(
        "git",
        ["rev-parse", "--show-toplevel", "--abbrev-ref", "HEAD"],
        { cwd, on },
      );
      const lines = git.stdout.split("\n").filter(Boolean);
      if (git.code === 0 && lines.length === 2) top = lines[0];
    } catch {
      // The machine is away or git is missing: name it after CWD, as the app.
    }
  return !top || (!on && top === home()) ? "~" : base(top);
}

// The checkout folder CWD is in, on machine ON (null: this one), as
// `{ top, name }`: `top` is the checkout's root and `name` its repo's, taken
// from the repo's own folder, so a jj workspace or Git worktree is named
// after the repo it belongs to. A jj checkout is read as jj sees it, else a
// Git one; null outside a repo or when neither answers (the machine is away).
// Mirrors desk-spaces' `check` and `checkJj` naming; change both together.
async function checkout(cwd, on) {
  try {
    // On this machine, the user's jj by its store path, since the app's PATH
    // depends on how the app was started; another machine resolves its own
    // `jj`. A dotfiles-paths.json without the entry leaves the bare name.
    const program = on ? "jj" : await cliPath("jj").catch(() => "jj");
    const root = await exec(
      program,
      ["--ignore-working-copy", "--no-pager", "--color=never", "root"],
      { cwd, on },
    ).catch(() => null);
    if (root?.code === 0) {
      const top = root.stdout.trim();
      // A secondary workspace's .jj/repo is a file naming the shared repo folder.
      const pointer = await exec("cat", [`${top}/.jj/repo`], { cwd, on });
      const repo =
        pointer.code === 0
          ? resolve(`${top}/.jj`, pointer.stdout.trim())
          : `${top}/.jj/repo`;
      return { top, name: base(repo.replace(/\/\.jj\/repo$/, "")) };
    }

    const git = await exec(
      "git",
      [
        "rev-parse",
        "--path-format=absolute",
        "--show-toplevel",
        "--git-common-dir",
      ],
      { cwd, on },
    );
    if (git.code !== 0) return null;
    const [top, common] = git.stdout.trim().split("\n");
    const name = common.endsWith("/.git")
      ? base(common.slice(0, -5))
      : base(common).replace(/\.git$/, "");
    return { top, name };
  } catch {
    return null;
  }
}

// These mirror desk-spaces: its avatar colors, and its path helpers.

// What a stored color name looks like on an avatar (the same in every mod
// that draws space avatars): one strong color per hue, light and dark alike.
const MARK = {
  ansi6: "#22a99a",
  ansi3: "#e3814f",
  ansi4: "#5b8def",
  ansi5: "#8b7cf6",
  ansi2: "#3fae6a",
  ansi1: "#d9649a",
};

const base = (path) => path.replace(/\/+$/, "").split("/").pop();

// `path` made absolute against `from`, without "." or ".." segments.
const resolve = (from, path) => {
  const out = [];
  for (const part of (path.startsWith("/") ? path : `${from}/${path}`).split(
    "/",
  )) {
    if (part === "..") out.pop();
    else if (part && part !== ".") out.push(part);
  }
  return `/${out.join("/")}`;
};
