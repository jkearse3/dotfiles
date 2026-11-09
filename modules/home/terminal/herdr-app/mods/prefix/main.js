// A tmux-style prefix mode for the Herdr app: `mod.open:prefix` opens this
// invisible popup, which takes the keyboard, reads the next keystroke, and
// runs the action bound to it. Esc or an unbound keystroke leaves prefix mode
// without acting. The popup has no frame and draws nothing; the app reads its
// `mod.json` size of 1 as a fraction of the window (full width, not 1px), and
// an empty popup takes no height, so it covers no visible area.
//
// The bindings are the `prefix` attribute of the dotfiles' `keys.nix`, which
// the Home Manager module validates and writes to `bindings.json` in this
// folder (keystroke -> keys.json action). An action is a `name:value`
// command, which `run` accepts as is, or `send:<control character>`, which
// this mod types into the terminal that was focused when prefix mode opened
// (`ctrl-b ctrl-b` sends a literal ctrl-b).
//
// The popup reads most keystrokes in `on_key_down`, but the app's keymap
// handles a keystroke it binds before that listener runs, and `global`
// binds `ctrl-b` to `mod.open:prefix`, which would close the popup instead.
// So `keys.nix` binds `ctrl-b` in the `mod:prefix` section, whose key
// context (this mod's) is deeper and wins, to `prefix.ctrl-b`, which the
// app delivers to `nextCommand()` here. The app reinstalls that binding on
// every keys.json reload, so this mod binds no keys itself. The
// build rejects any other prefix keystroke that `global`, a `layout:`
// section, or `mod:prefix` binds, since the app would take it first. Esc is
// the app's too (`overlay.close`): it closes the popup, and `close` turns
// the PREFIX pill off.
//
// While prefix mode is on, the `prefix-status` status bar shows a "PREFIX"
// pill and key hints built from the bindings: this mod publishes the hints
// with `setShared("prefix", { hints })` and then runs `prefix-status.on`,
// because the bar redraws on a command, not on setShared alone. Leaving runs
// `prefix-status.off`, then closes the popup, then runs the action: an
// action that opens an overlay or moves focus runs after the popup gives
// the keyboard back. The bar is updated only when the shown layout has it
// (today only `desk`): with no `prefix-status` on screen the app answers
// those commands with an "unknown command" error toast, so on other layouts
// prefix mode works without an indicator.

import { View, div } from "gpui-kit";
import {
  appHome,
  closeOverlay,
  focused,
  hc,
  layout,
  notify,
  nextCommand,
  props,
  readTextFile,
  run,
  setShared,
} from "herdr";

const TITLE = "Prefix";

// The command keys.json's `mod:prefix` section sends (as `prefix.ctrl-b`)
// for `ctrl-b` while prefix mode is open; it handles `ctrl-b` as the prefix
// keystroke.
const CTRL_B_COMMAND = "ctrl-b";

// The status bar mod that shows the PREFIX pill and hints.
const STATUS_MOD = "prefix-status";

// Runs the status bar's COMMAND (`on` or `off`) when the shown layout has
// the bar, and does nothing otherwise.
function runStatusCommand(command) {
  if (namesMod(layout(), STATUS_MOD)) run(`${STATUS_MOD}.${command}`);
}

// Whether NODE, a layout document or part of one, names mod NAME as a `mod`
// value at any depth, the rule the build's layout check also uses.
function namesMod(node, name) {
  if (node === null || typeof node !== "object") return false;
  if (node.mod === name) return true;
  return Object.values(node).some((child) => namesMod(child, name));
}

// Hint labels, in the order the status bar shows them. Each entry matches a
// bound action exactly, or else by its command name (the part before `:`).
const LABELS = [
  ["pane.split", "split"],
  ["pane.go", "focus"],
  ["tab.new", "new tab"],
  ["tab.select", "tab"],
  ["mod.open:find", "find"],
  ["mod.open:goto", "go to"],
  ["pane.zoom", "zoom"],
  ["pane.close", "close"],
  ["app.help", "help"],
];

// Reads `bindings.json` as a Map of keystroke -> action. Throws when the
// file is missing or is not a JSON object, which a Home Manager switch fixes.
async function loadBindings() {
  const path = `${appHome()}/mods/prefix/bindings.json`;
  const text = await readTextFile(path);
  let parsed = null;
  try {
    parsed = text === null ? null : JSON.parse(text);
  } catch {
    // Reported below with the other unusable contents.
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(
      `${path} is missing or not a JSON object; run a Home Manager switch.`,
    );
  }
  return new Map(Object.entries(parsed));
}

// The status bar's `[keys, label]` hints for BINDINGS, in LABELS order,
// skipping labels no keystroke is bound to, and ending with Esc.
function hintsFor(bindings) {
  const keysByLabel = new Map(LABELS.map(([, label]) => [label, []]));
  for (const [key, action] of bindings) {
    const label = labelFor(action);
    if (label) keysByLabel.get(label).push(key);
  }

  const hints = [];
  for (const [label, keys] of keysByLabel) {
    if (keys.length > 0) hints.push([joinKeys(keys), label]);
  }
  hints.push(["esc", "cancel"]);
  return hints;
}

// The LABELS label for ACTION, or undefined when it has none.
function labelFor(action) {
  const command = action.split(":")[0];
  const exact = LABELS.find(([match]) => match === action);
  return (exact ?? LABELS.find(([match]) => match === command))?.[1];
}

// Spells the keystrokes `keys` as one hint: `1–9` for three or more
// consecutive digits, `hjkl` for three or more single letters, otherwise
// `v / -`, with letters and digits before punctuation.
function joinKeys(keys) {
  const isPunctuation = (key) => /^[^a-z0-9]$/i.test(key);
  const sorted = [...keys].sort(
    (a, b) => isPunctuation(a) - isPunctuation(b) || a.localeCompare(b),
  );

  if (sorted.length >= 3 && sorted.every((key) => /^[0-9]$/.test(key))) {
    const digits = sorted.map(Number);
    if (digits.every((digit, i) => digit === digits[0] + i)) {
      return `${digits[0]}–${digits[digits.length - 1]}`;
    }
  }
  if (sorted.length >= 3 && sorted.every((key) => /^[a-z]$/i.test(key))) {
    return sorted.join("");
  }
  return sorted.join(" / ");
}

// Tells the person a `send:` keystroke did not reach the terminal.
function reportSendFailure(body) {
  notify({
    title: TITLE,
    body,
    level: "error",
  });
}

export default class Prefix extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    // `herdr-app check` renders the mod with no props, outside an overlay.
    // Start nothing then.
    const overlay = props()?.overlay;
    if (!overlay) return;

    this.handle.focus();
    // Captured now, while it still names the terminal the person was in.
    this.target = focused();
    // Keystroke -> action once loaded; until then, the first key pressed
    // waits in `pendingKey`.
    this.bindings = undefined;
    this.pendingKey = undefined;

    cx.spawn(async (_cx) => {
      try {
        this.bindings = await loadBindings();
      } catch (error) {
        closeOverlay(overlay);
        notify({
          title: TITLE,
          body: String(error?.message ?? error),
          level: "error",
        });
        return;
      }

      setShared("prefix", { hints: hintsFor(this.bindings) });
      runStatusCommand("on");
      if (this.pendingKey) this.handleKey(this.pendingKey);
    });

    // Runs while the popup is open: closing it cancels this loop, and
    // nextCommand() rejects only when the app quits.
    cx.spawn(async (_cx) => {
      try {
        for (;;) {
          const command = await nextCommand();
          if (command === CTRL_B_COMMAND)
            this.receiveKey({ keystroke: "ctrl-b" });
        }
      } catch {}
    });
  }

  // Runs however the popup goes: a key, Esc, a click outside, or quit. Turns
  // the status bar's PREFIX pill off when the shown layout has the bar.
  async close(_cx) {
    runStatusCommand("off");
  }

  onKey(e, cx) {
    cx.stop_propagation();
    this.receiveKey({
      keystroke: e.keystroke,
      key_char: e.key_char,
    });
  }

  // Handles KEY now, or keeps it as `pendingKey` until the bindings load
  // (only the first key pressed before then is kept).
  receiveKey(key) {
    if (this.bindings) this.handleKey(key);
    else if (!this.pendingKey) this.pendingKey = key;
  }

  // Leaves prefix mode, running the action bound to KEY, if any. `?` is
  // bound by the character it types, so the keystroke is tried first, then
  // the character.
  handleKey({ keystroke, key_char }) {
    if (keystroke === "escape") return this.dismiss();
    const action =
      this.bindings.get(keystroke) ??
      (key_char ? this.bindings.get(key_char) : undefined);
    this.dismiss(action && (() => this.perform(action)));
  }

  // Ends prefix mode, closes the popup, then runs THEN (if any).
  dismiss(then) {
    runStatusCommand("off");
    closeOverlay(props().overlay);
    if (then) then();
  }

  // Runs one bound action. The build guarantees a `send:` action carries
  // exactly one control character (U+0001-U+001A), typed as its ctrl- key
  // into the captured terminal; with no terminal captured it does nothing,
  // and a failed `hc keys` shows an error notification.
  perform(action) {
    if (!action.startsWith("send:")) return run(action);

    const terminal = this.target?.terminal;
    if (!terminal) return;
    const code = action.charCodeAt("send:".length);
    const key = "ctrl+" + String.fromCharCode(0x60 + code);
    hc(["keys", terminal, key]).then(
      (r) => {
        if (r.code !== 0) {
          reportSendFailure(r.stderr.trim() || `hc keys exited with ${r.code}`);
        }
      },
      (error) => reportSendFailure(String(error?.message ?? error)),
    );
  }

  // An invisible key catcher: the status bar draws the indicator.
  render(_cx) {
    return div()
      .id("prefix")
      .track_focus(this.handle)
      .on_key_down((e, cx) => this.onKey(e, cx))
      .size_full();
  }
}
