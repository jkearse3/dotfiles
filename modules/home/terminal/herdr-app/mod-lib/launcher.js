// A launcher mod opens a program in a popup terminal, so a key binding can
// reach that program: `mod.open` takes only a mod name. The launcher is an
// invisible dialog (its `mod.json` overlay) that starts the program in a core
// terminal, closes itself, and opens a modal dialog showing that terminal
// under the `popup` mod's title bar. `launch` is that whole sequence; a
// launcher supplies only its title and how it chooses the program, arguments
// and folder.
//
// Each mod that uses this file links it, with the `paths.js` it imports, into
// its own folder (`mods/<mod>/launcher.js` -> `../../mod-lib/launcher.js`),
// and the deploy tree copies the file in place of the link. The app refuses
// imports that leave a mod's own folder; `./launcher.js` beside the
// importing file is allowed.

import { closeOverlay, hc, notify, openOverlay, props } from "herdr";
import { cliPath } from "./paths.js";

// Runs the launcher opened as overlay `props().overlay`, titled TITLE.
// PREPARE runs synchronously, before anything starts, and returns either
// `{ refuse: message }`, which closes the launcher and shows MESSAGE as a
// warning, or `{ cli, folder, args }`: the `dotfiles-paths.json` name of the
// program to run, the folder to start it in, and its arguments. The launcher
// then starts the program and shows it in a popup, or closes and shows the
// error. It waits for `hc run` while still open, because closing it cancels
// its pending tasks and would leave the started terminal with no popup.
export function launch(cx, { title, prepare }) {
  const overlay = launcherOverlay();
  if (!overlay) return;

  const plan = prepare();
  if (plan.refuse) {
    refuse(overlay, title, plan.refuse);
    return;
  }

  cx.spawn(async (_cx) => {
    let terminal;
    try {
      const path = await cliPath(plan.cli);
      terminal = await startTerminal(plan.folder, [path, ...plan.args]);
    } catch (error) {
      fail(overlay, title, error);
      return;
    }

    showPopup(overlay, { terminal, title });
  });
}

// The overlay this launcher was opened as, or undefined. `herdr-app check`
// renders the mod with no props, outside an overlay. Start nothing then: `hc`
// would start a core when none runs.
export function launcherOverlay() {
  return props()?.overlay;
}

// Closes the launcher OVERLAY and shows why it starts nothing as a warning.
export function refuse(overlay, title, body) {
  closeOverlay(overlay);
  notify({ title, body, level: "warning" });
}

// Closes the launcher OVERLAY and shows ERROR, which stopped the launch.
export function fail(overlay, title, error) {
  closeOverlay(overlay);
  notify({
    title,
    body: String(error?.message ?? error),
    level: "error",
  });
}

// Starts ARGV in FOLDER in a new core terminal and returns its address. No
// herdr labels, so it never becomes a pane; no parent, so it never types
// notes into the terminal that happened to be focused; `--rm`, so no
// finished record stays behind.
export async function startTerminal(folder, argv) {
  const r = await hc([
    "run",
    "--bg",
    "--rm",
    "--no-parent",
    "--no-notify",
    "--json",
    "--cwd",
    folder,
    "--",
    ...argv,
  ]);
  if (r.code !== 0) {
    throw new Error(r.stderr.trim() || `hc run exited with ${r.code}`);
  }
  const address = JSON.parse(r.stdout).address;
  if (!address) throw new Error("hc run printed no terminal address.");
  return address;
}

// Closes the launcher OVERLAY and shows TERMINAL in a modal dialog of
// fractional size WIDTH x HEIGHT, under the `popup` mod's 30px title bar
// showing TITLE; POPUP adds props for the `popup` mod.
//
// The order matters: in one synchronous turn the launcher closes itself
// before opening the popup. Opening focuses the popup's terminal, whereas a
// dialog closed afterwards would hand the keyboard to the popup's frame
// instead (herdr-app `src/window.rs` `remove_overlay`, `restore_focus`).
export function showPopup(
  overlay,
  { terminal, title, width = 0.6, height = 0.5, popup = {} },
) {
  closeOverlay(overlay);
  openOverlay({
    kind: "dialog",
    // A click beside it does not close it; Esc goes to the program in the
    // popup.
    modal: true,
    width,
    height,
    layout: {
      type: "column",
      children: [
        {
          type: "block",
          size: { px: 30 },
          content: { mod: "popup", props: { terminal, title, ...popup } },
        },
        { type: "block", content: { terminal } },
      ],
    },
  });
}
