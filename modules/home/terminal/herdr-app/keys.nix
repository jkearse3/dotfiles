# The Herdr TUI's `ctrl-b` prefix keymap (its 0.9.5 defaults and the user
# bindings in `../herdr/config.toml`) for the Herdr app, as two attributes:
#
# - `sections`: keys.json sections (`global`, `terminal`, ...) mapping a key
#   or chord to an action. `global` binds `ctrl-b` alone to
#   `mod.open:prefix`, which opens prefix mode (the `prefix` mod), and
#   `mod:prefix` binds it to `prefix.ctrl-b`, which the open prefix mod
#   takes as a prefix keystroke.
# - `prefix`: what prefix mode does and shows. Its `bindings` map the one
#   keystroke typed in prefix mode to an action; Esc or an unmapped keystroke
#   leaves prefix mode without acting. Its `hints` label those actions in the
#   status bar. The module writes both to the `prefix` mod's `bindings.json`.
#
# The module merges `sections` over the app's own `defaults/keys.macos.json`,
# so its `cmd-` keys stay bound beside them, and fails the build on bindings
# that break the rules stated in `keys-check.jq`.
#
# A chord is space-separated keystrokes. Spellings follow the app's key
# parser (vendored gpui `Keystroke::parse`): `?` matches shift-/ because
# macOS reports the shifted character, `-` is the minus key, and shifted
# letters are `shift-<letter>`.
#
# TUI actions left unmapped because the app has no equivalent: reload config
# (the app reloads its files live), open notification target, rename pane,
# edit scrollback, copy mode, cycle pane next/previous, resize mode, and the
# TUI's navigate-mode keys (`up`/`down`/`j`/`k` for workspaces, `h`/`j`/`k`/`l`
# for panes).
{
  sections = {
    global = {
      "ctrl-b" = "mod.open:prefix";
      # The app's `cmd-p` opens its built-in picker; open `goto`, the personal
      # clone with ctrl-j/ctrl-k, instead.
      "cmd-p" = "mod.open:goto";
      # Likewise `cmd-shift-p` opens `palette`, the personal copy of the
      # command palette with ctrl-j/ctrl-k, instead of `app.palette`.
      "cmd-shift-p" = "mod.open:palette";
      # The app's `cmd-n` makes a space in the focused terminal's folder; open
      # `space-new`, the folder picker, which offers that folder first,
      # instead.
      "cmd-n" = "mod.open:space-new";
    };
    # While prefix mode is open, `ctrl-b` goes to the prefix mod as a
    # command instead of reopening it: this section's key context is deeper
    # than `global`'s, and the app reinstalls it on every keys.json reload.
    "mod:prefix" = {
      "ctrl-b" = "prefix.ctrl-b";
    };
  };

  prefix = {
    bindings = {
      "?" = "app.help";
      "s" = "app.settings";

      # The TUI's new-workspace key picks the folder with fzf (`space-new`),
      # like `cmd-n`.
      "shift-n" = "mod.open:space-new";
      "shift-w" = "space.rename";
      # Renames every space at once in a dialog.
      "ctrl-w" = "mod.open:space-rename-all";
      "shift-d" = "space.close";
      # New jj workspaces: `ctrl-g` (the TUI user binding) uses the focused
      # terminal's repository, and `shift-g` picks with fzf among the focused
      # terminal's repository and those of the spaces open on this machine, the
      # focused one first. Both take the jj path, never the app's own Git
      # worktree commands, which would bypass jj: every checkout here is a jj
      # workspace. In the TUI, `shift-g` stays Herdr's Git new-worktree key.
      "shift-g" = "mod.open:jj-workspace-pick";
      "ctrl-g" = "mod.open:jj-workspace-new";
      "shift-q" = "mod.open:jj-workspace-remove";
      # The TUI's workspace picker and go-to both open `goto`, the personal
      # clone of the app's picker with ctrl-j/ctrl-k.
      "w" = "mod.open:goto";
      "g" = "mod.open:goto";
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
      # `global` binds `ctrl-b` too; `mod:prefix` sends it to the prefix mod
      # so this binding wins while prefix mode is open.
      "ctrl-b" = "send:" + builtins.fromJSON ''"\u0002"'';
    };

    # The status bar's hints while prefix mode is on, in the order it shows
    # them. Each entry matches a bound action exactly, or else by its command
    # name (the part before `:`). A hint shows its label after the keys of
    # every binding that matches it, and only when some binding does. The
    # `prefix` mod appends Esc -> cancel.
    hints = [
      {
        action = "pane.split";
        label = "split";
      }
      {
        action = "pane.go";
        label = "focus";
      }
      {
        action = "tab.new";
        label = "new tab";
      }
      {
        action = "tab.select";
        label = "tab";
      }
      {
        action = "mod.open:find";
        label = "find";
      }
      {
        action = "mod.open:goto";
        label = "go to";
      }
      {
        action = "pane.zoom";
        label = "zoom";
      }
      {
        action = "pane.close";
        label = "close";
      }
      {
        action = "app.help";
        label = "help";
      }
    ];
  };
}
