// Shows `herdr-find`'s fzf picker over agents and spaces in a popup
// terminal, so a key binding (`ctrl-b f`) can reach it: `mod.open` takes
// only a mod name. This launcher is an invisible dialog that hands the
// picker's terminal to a modal dialog whose `popup` block runs
// `herdr-find show` when it opens and `herdr-find reset` when it closes.
//
// The picker is one long-lived core terminal named `herdr-find`, running
// `herdr-find serve --host app`: fzf stays running hidden between presses
// and loads fresh rows on each `show`. A press takes one of three paths:
// - Reuse: a live `herdr-find` terminal runs the current `herdr-find`, so
//   the launcher shows it.
// - Upgrade: it runs another `herdr-find` (an older generation after a
//   switch), so the launcher kills it, waiting with `hc kill` until it has
//   ended, and starts a new one.
// - Start: none is live, so the launcher starts one with `hc run --name`.
//   When the name is taken (a concurrent press started it), the launcher
//   shows that terminal if it runs the current `herdr-find`.
// The only terminal a press can start is this singleton, so a launch
// cancelled by the launcher closing leaves nothing unowned: the next press
// finds it by name.
//
// The launcher waits for `hc` while still open, because closing it cancels
// its pending tasks; `showPopup` in `launcher.ts` says why it then closes
// itself before opening the popup. The reuse path awaits nothing between
// reading `terminals()` and opening the popup, so the terminal it found
// cannot end in between unnoticed and the frame appears at once.
//
// `launcher.ts` and `paths.ts` beside this file are links to the shared
// copies in `mod-lib/`.

import { View, div } from "gpui-kit";
import { focused, hc, home, spaces, terminals } from "herdr";
import { fail, launcherOverlay, refuse, showPopup } from "./launcher.js";
import { cliPath } from "./paths.js";

const TITLE = "Find";
// The core terminal name of the one long-lived app picker.
const PICKER_NAME = "herdr-find";

// Whether RECORD (an `hc ls`/`hc get` terminal record) is a live picker
// terminal running the `herdr-find` at FIND_PATH.
function runsCurrentPicker(record, findPath) {
  return record?.state === "live" && record.argv?.[0] === findPath;
}

// Returns the address of the live `herdr-find` terminal running FIND_PATH,
// as `hc get` reports it, or undefined.
async function getCurrentPicker(findPath) {
  const r = await hc(["get", PICKER_NAME, "--json"]);
  if (r.code !== 0) return undefined;
  let record;
  try {
    record = JSON.parse(r.stdout);
  } catch {
    return undefined;
  }
  return runsCurrentPicker(record, findPath) ? record.address : undefined;
}

// Starts `FIND_PATH serve --host app` in the picker terminal and returns its
// address. No herdr labels, so it never becomes a pane; no parent, so it
// never types notes into the terminal that happened to be focused; `--rm`,
// so a picker that exits leaves no finished record holding the name.
async function startPicker(findPath) {
  const r = await hc([
    "run",
    "--bg",
    "--rm",
    "--no-parent",
    "--no-notify",
    "--json",
    "--name",
    PICKER_NAME,
    "--cwd",
    home(),
    "--",
    findPath,
    "serve",
    "--host",
    "app",
  ]);
  if (r.code !== 0) {
    const running = await getCurrentPicker(findPath);
    if (running) return running;
    throw new Error(r.stderr.trim() || `hc run exited with ${r.code}`);
  }
  const address = JSON.parse(r.stdout).address;
  if (!address) throw new Error("hc run printed no terminal address.");
  return address;
}

// Closes LAUNCHER and opens the popup showing the picker TERMINAL, which
// loads rows for the caller (SPACE_ID, CALLER) when it opens and is reset
// when it closes. Synchronous, so the reuse path awaits nothing in between.
function showPicker(launcher, terminal, findPath, spaceId, caller) {
  const show = [
    "show",
    "--overlay",
    "{overlay}",
    "--caller-workspace",
    spaceId,
    ...(caller ? ["--caller-pane", caller] : []),
  ];

  showPopup(launcher, {
    terminal,
    title: TITLE,
    width: 0.8,
    height: 0.7,
    popup: {
      keepTerminal: true,
      openCommand: { command: findPath, args: show },
      closeCommand: {
        command: findPath,
        args: ["reset", "--overlay", "{overlay}"],
      },
    },
  });
}

export default class Find extends View {
  init(_props, cx) {
    const overlay = launcherOverlay();
    if (!overlay) return;

    const space = spaces().find((s) => s.active);
    if (!space) {
      refuse(overlay, TITLE, "No space is shown.");
      return;
    }
    const caller = focused()?.terminal;

    cx.spawn(async (_cx) => {
      try {
        const findPath = await cliPath("herdr-find");
        const live = terminals().find(
          (t) => t.name === PICKER_NAME && t.state === "live",
        );
        if (runsCurrentPicker(live, findPath)) {
          showPicker(overlay, live.address, findPath, space.id, caller);
          return;
        }
        // Whatever `hc kill` returns, start: the old picker may have ended
        // already, and a kill that failed leaves the name taken, which
        // `startPicker` reports.
        if (live) await hc(["kill", live.address]);
        const terminal = await startPicker(findPath);
        showPicker(overlay, terminal, findPath, space.id, caller);
      } catch (error) {
        fail(overlay, TITLE, error);
      }
    });
  }

  render(_cx) {
    return div();
  }
}
