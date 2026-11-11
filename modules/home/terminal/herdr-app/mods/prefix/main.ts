// A tmux-style prefix mode for the Herdr app: `mod.open:prefix` opens this
// invisible popup, which takes the keyboard, reads the next keystroke, and
// runs the action bound to it. Esc or an unbound keystroke leaves prefix mode
// without acting. The popup has no frame and draws nothing; the app reads its
// `mod.json` size of 1 as a fraction of the window (full width, not 1px), and
// an empty popup takes no height, so it covers no visible area.
//
// The Home Manager module validates the `prefix` attribute of the dotfiles'
// `keys.nix` and writes it to `bindings.json` in this folder: `bindings`
// maps a keystroke to a keys.json action, and `hints` lists the status bar's
// `{action, label}` hints in the order it shows them. An action is a
// `name:value` command, which `run` accepts as is, or `send:<control
// character>`, which this mod types into the terminal that was focused when
// prefix mode opened (`ctrl-b ctrl-b` sends a literal ctrl-b).
//
// The popup reads most keystrokes in `on_key_down`, but the app's keymap
// handles a keystroke it binds before that listener runs, and `global`
// binds `ctrl-b` to `mod.open:prefix`, which would close the popup instead.
// So `keys.nix` binds `ctrl-b` in the `mod:prefix` section, whose key
// context (this mod's) is deeper and wins, to `prefix.ctrl-b`, which the
// app delivers to `nextCommand()` here. The app reinstalls that binding on
// every keys.json reload, so this mod binds no keys itself. The build's
// `keys-check.jq` rejects any other prefix keystroke the app would take
// first. Esc is the app's too (`overlay.close`): it closes the popup, and
// `close` turns the PREFIX pill off.
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
import type { AsyncContext, Context, FocusHandle, KeyEvent } from "gpui-kit";
import type { Props } from "gpui-shell";
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

// What `bindings.json` holds: the `prefix` attribute of `keys.nix`, which
// the Home Manager module validates before writing it.
interface PrefixBindingsFile {
  // Keystroke -> keys.json action.
  bindings: Record<string, string>;
  hints: PrefixHint[];
}

// One status bar hint: the LABEL shown after the keys of every binding whose
// action is ACTION, or whose command name (the part before `:`) is ACTION.
interface PrefixHint {
  action: string;
  label: string;
}

// The parts of a keystroke that select a binding.
type PrefixKey = Pick<KeyEvent, "keystroke" | "key_char">;

// Runs the status bar's COMMAND (`on` or `off`) when the shown layout has
// the bar, and does nothing otherwise.
function runStatusCommand(command: "on" | "off"): void {
  if (namesMod(layout(), STATUS_MOD)) run(`${STATUS_MOD}.${command}`);
}

// Whether NODE, a layout document or part of one, names mod NAME as a `mod`
// value at any depth, the rule the build's layout check also uses.
function namesMod(node: unknown, name: string): boolean {
  if (node === null || typeof node !== "object") return false;
  if ((node as { mod?: unknown }).mod === name) return true;
  return Object.values(node).some((child) => namesMod(child, name));
}

// Reads `bindings.json` as `{ bindings, hints }`: a Map of keystroke ->
// action, and the `{action, label}` hints. Throws when the file is missing,
// or is not a JSON object whose `bindings` is an object and `hints` an
// array, which a Home Manager switch fixes.
async function loadBindings(): Promise<{
  bindings: Map<string, string>;
  hints: PrefixHint[];
}> {
  const path = `${appHome()}/mods/prefix/bindings.json`;
  const text = await readTextFile(path);
  let parsed: PrefixBindingsFile | null = null;
  try {
    parsed = text === null ? null : (JSON.parse(text) as PrefixBindingsFile);
  } catch {
    // Reported below with the other unusable contents.
  }
  const bindings = parsed?.bindings;
  const hints = parsed?.hints;
  if (
    bindings === null ||
    typeof bindings !== "object" ||
    Array.isArray(bindings) ||
    !Array.isArray(hints)
  ) {
    throw new Error(
      `${path} is missing or not a JSON object with bindings and hints; run a Home Manager switch.`,
    );
  }
  return { bindings: new Map(Object.entries(bindings)), hints };
}

// The status bar's `[keys, label]` hints for BINDINGS, in HINTS order,
// skipping labels no keystroke is bound to, and ending with Esc.
function hintsFor(
  bindings: Map<string, string>,
  hints: PrefixHint[],
): [string, string][] {
  const keysByLabel = new Map(
    hints.map(({ label }): [string, string[]] => [label, []]),
  );
  for (const [key, action] of bindings) {
    const label = labelFor(action, hints);
    if (label) keysByLabel.get(label)!.push(key);
  }

  const shown: [string, string][] = [];
  for (const [label, keys] of keysByLabel) {
    if (keys.length > 0) shown.push([joinKeys(keys), label]);
  }
  shown.push(["esc", "cancel"]);
  return shown;
}

// The label of the HINTS entry matching ACTION, exactly or else by its
// command name (the part before `:`), or undefined when none matches.
function labelFor(action: string, hints: PrefixHint[]): string | undefined {
  const command = action.split(":")[0];
  const exact = hints.find((hint) => hint.action === action);
  return (exact ?? hints.find((hint) => hint.action === command))?.label;
}

// Spells the keystrokes `keys` as one hint: `1–9` for three or more
// consecutive digits, `hjkl` for three or more single letters, otherwise
// `v / -`, with letters and digits before punctuation.
function joinKeys(keys: string[]): string {
  const isPunctuation = (key: string) => /^[^a-z0-9]$/i.test(key);
  const sorted = [...keys].sort(
    (a, b) =>
      Number(isPunctuation(a)) - Number(isPunctuation(b)) || a.localeCompare(b),
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
function reportSendFailure(body: string): void {
  notify({
    title: TITLE,
    body,
    level: "error",
  });
}

export default class Prefix extends View {
  declare handle: FocusHandle;
  declare target: ReturnType<typeof focused>;
  declare bindings: Map<string, string> | undefined;
  declare pendingKey: PrefixKey | undefined;

  init(_props: Props | undefined, cx: AsyncContext): void {
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
      let hints;
      try {
        ({ bindings: this.bindings, hints } = await loadBindings());
      } catch (error) {
        closeOverlay(overlay);
        notify({
          title: TITLE,
          body: String(
            (error as { message?: unknown } | null)?.message ?? error,
          ),
          level: "error",
        });
        return;
      }

      setShared("prefix", { hints: hintsFor(this.bindings, hints) });
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
  async close(_cx: AsyncContext): Promise<void> {
    runStatusCommand("off");
  }

  onKey(e: KeyEvent, cx: Context): void {
    cx.stop_propagation();
    this.receiveKey({
      keystroke: e.keystroke,
      key_char: e.key_char,
    });
  }

  // Handles KEY now, or keeps it as `pendingKey` until the bindings load
  // (only the first key pressed before then is kept).
  receiveKey(key: PrefixKey): void {
    if (this.bindings) this.handleKey(key);
    else if (!this.pendingKey) this.pendingKey = key;
  }

  // Leaves prefix mode, running the action bound to KEY, if any. `?` is
  // bound by the character it types, so the keystroke is tried first, then
  // the character.
  handleKey({ keystroke, key_char }: PrefixKey): void {
    if (keystroke === "escape") return this.dismiss();
    const action =
      this.bindings!.get(keystroke) ??
      (key_char ? this.bindings!.get(key_char) : undefined);
    this.dismiss(action && (() => this.perform(action)));
  }

  // Ends prefix mode, closes the popup, then runs THEN (if any; `handleKey`
  // passes the empty string when the bound action is empty).
  dismiss(then?: (() => void) | ""): void {
    runStatusCommand("off");
    closeOverlay(props().overlay);
    if (then) then();
  }

  // Runs one bound action. The build's `keys-check.jq` guarantees a `send:`
  // action carries exactly one control character (U+0001-U+001A), typed as
  // its ctrl- key into the captured terminal; with no terminal captured it
  // does nothing, and a failed `hc keys` shows an error notification.
  perform(action: string) {
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
  render(_cx: Context) {
    return div()
      .id("prefix")
      .track_focus(this.handle)
      .on_key_down((e, cx) => this.onKey(e, cx))
      .size_full();
  }
}
