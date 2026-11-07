# The Herdr TUI's `ctrl-b` prefix keymap (its 0.9.5 defaults and the user
# bindings in `../herdr/config.toml`) for the Herdr app, as two attributes:
#
# - `sections`: keys.json sections (`global`, `terminal`, ...) mapping a key
#   or chord to an action.
# - `prefix`: the prefix bindings, mapping the keystroke typed after `ctrl-b`
#   to an action. The module renders each one as the `global` chord
#   `ctrl-b <keystroke>`.
#
# A key that opens a personal mod (under `mods/`) is mapped only alongside
# that mod, so keys whose mod is absent stay unbound. The module merges
# these over the app's own `defaults/keys.macos.json`, so its `cmd-` keys stay
# bound beside them, and fails the build on an action the app does not know.
#
# A chord is space-separated keystrokes. The app waits for the next key after
# `ctrl-b` with no timeout, and hands both keys to the terminal program when
# the pair is unbound, so `ctrl-b` itself must never be bound alone. Spellings
# follow the app's key parser (vendored gpui `Keystroke::parse`): `?` matches
# shift-/ because macOS reports the shifted character, `-` is the minus key,
# and shifted letters are `shift-<letter>`.
#
# TUI actions left unmapped because the app has no equivalent: reload config
# (the app reloads its files live), open notification target, rename pane,
# edit scrollback, copy mode, cycle pane next/previous, resize mode, and the
# TUI's navigate-mode keys (`up`/`down`/`j`/`k` for workspaces, `h`/`j`/`k`/`l`
# for panes).
{
  sections = {
    global = { };
  };

  prefix = {
    "?" = "app.help";
    "s" = "app.settings";

    "shift-n" = "space.new";
    "shift-w" = "space.rename";
    "shift-d" = "space.close";
    # The TUI's new-worktree key and the user's jj-workspace keys all take the
    # jj path: every checkout here is a jj workspace, and the app's own Git
    # worktree commands would bypass jj.
    "shift-g" = "mod.open:jj-workspace-new";
    "ctrl-g" = "mod.open:jj-workspace-new";
    "shift-q" = "mod.open:jj-workspace-remove";
    "ctrl-q" = "mod.open:jj-workspace-remove";
    # The TUI's workspace picker and go-to both open the app's built-in picker.
    "w" = "mod.open:picker";
    "g" = "mod.open:picker";
    # The TUI user binding for finding agents and workspaces with fzf.
    "f" = "mod.open:find";
    # The TUI's detach: closing the window leaves its terminals running.
    "q" = "window.close";

    "c" = "tab.new";
    "shift-t" = "tab.rename";
    "p" = "tab.prev";
    "n" = "tab.next";
    "1" = "tab.select:1";
    "2" = "tab.select:2";
    "3" = "tab.select:3";
    "4" = "tab.select:4";
    "5" = "tab.select:5";
    "6" = "tab.select:6";
    "7" = "tab.select:7";
    "8" = "tab.select:8";
    "9" = "tab.select:9";
    "shift-x" = "tab.close";

    "h" = "pane.go:left";
    "j" = "pane.go:down";
    "k" = "pane.go:up";
    "l" = "pane.go:right";
    "shift-h" = "pane.swap:left";
    "shift-j" = "pane.swap:down";
    "shift-k" = "pane.swap:up";
    "shift-l" = "pane.swap:right";
    "v" = "pane.split:right";
    "-" = "pane.split:down";
    "x" = "pane.close";
    "z" = "pane.zoom";

    "b" = "layout.toggle:sidebar";

    # tmux's literal prefix: one `ctrl-b` (U+0002) typed into the terminal.
    "ctrl-b" = "send:" + builtins.fromJSON ''"\u0002"'';
  };
}
