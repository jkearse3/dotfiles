# The Herdr TUI's `ctrl-b` prefix keymap (its 0.9.5 defaults and the user
# bindings in `../herdr/config.toml`) as Herdr app chords. A key that opens a
# personal mod (under `mods/`) is mapped only alongside that mod, so keys
# whose mod is absent stay unbound. The module merges
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
  global = {
    "ctrl-b ?" = "app.help";
    "ctrl-b s" = "app.settings";

    "ctrl-b shift-n" = "space.new";
    "ctrl-b shift-w" = "space.rename";
    "ctrl-b shift-d" = "space.close";
    # The TUI's new-worktree key and the user's jj-workspace keys all take the
    # jj path: every checkout here is a jj workspace, and the app's own Git
    # worktree commands would bypass jj.
    "ctrl-b shift-g" = "mod.open:jj-workspace-new";
    "ctrl-b ctrl-g" = "mod.open:jj-workspace-new";
    "ctrl-b shift-q" = "mod.open:jj-workspace-remove";
    "ctrl-b ctrl-q" = "mod.open:jj-workspace-remove";
    # The TUI's workspace picker and go-to both open the app's built-in picker.
    "ctrl-b w" = "mod.open:picker";
    "ctrl-b g" = "mod.open:picker";
    # The TUI user binding for finding agents and workspaces with fzf.
    "ctrl-b f" = "mod.open:find";
    # The TUI's detach: closing the window leaves its terminals running.
    "ctrl-b q" = "window.close";

    "ctrl-b c" = "tab.new";
    "ctrl-b shift-t" = "tab.rename";
    "ctrl-b p" = "tab.prev";
    "ctrl-b n" = "tab.next";
    "ctrl-b 1" = "tab.select:1";
    "ctrl-b 2" = "tab.select:2";
    "ctrl-b 3" = "tab.select:3";
    "ctrl-b 4" = "tab.select:4";
    "ctrl-b 5" = "tab.select:5";
    "ctrl-b 6" = "tab.select:6";
    "ctrl-b 7" = "tab.select:7";
    "ctrl-b 8" = "tab.select:8";
    "ctrl-b 9" = "tab.select:9";
    "ctrl-b shift-x" = "tab.close";

    "ctrl-b h" = "pane.go:left";
    "ctrl-b j" = "pane.go:down";
    "ctrl-b k" = "pane.go:up";
    "ctrl-b l" = "pane.go:right";
    "ctrl-b shift-h" = "pane.swap:left";
    "ctrl-b shift-j" = "pane.swap:down";
    "ctrl-b shift-k" = "pane.swap:up";
    "ctrl-b shift-l" = "pane.swap:right";
    "ctrl-b v" = "pane.split:right";
    "ctrl-b -" = "pane.split:down";
    "ctrl-b x" = "pane.close";
    "ctrl-b z" = "pane.zoom";

    "ctrl-b b" = "layout.toggle:sidebar";

    # tmux's literal prefix: one `ctrl-b` (U+0002) typed into the terminal.
    "ctrl-b ctrl-b" = "send:" + builtins.fromJSON ''"\u0002"'';
  };
}
