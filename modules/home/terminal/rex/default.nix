{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Rex installs itself outside Nix, and its updater replaces the CLI under
  # `Versions/Current`, so this path stays valid across Rex updates.
  rexCli = "${config.home.homeDirectory}/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex";

  applyTheme = pkgs.writeShellApplication {
    name = "rex-apply-theme";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = builtins.readFile ./apply-theme.sh;
  };
in
{
  home = {
    # Puts `rex` on PATH outside Rex terminals too, for the skill below, which
    # calls bare `rex`.
    packages = [
      (pkgs.writeShellScriptBin "rex" ''
        exec ${pkgs.lib.escapeShellArg rexCli} "$@"
      '')
    ];

    file = {
      # Rex reads its keybindings from this file. Rex itself is installed as a
      # macOS app outside Nix, so this module only manages its config.
      ".config/rex/init.lua".source = ./init.lua;

      # Tokyo Night as a Ghostty theme file, from the same tokyonight.nvim
      # that Neovim uses, for Rex's Settings > Theme > Import
      # (`client.theme.import`). Rex ships no Tokyo Night of its own.
      ".config/rex/themes/tokyonight_night".source =
        "${pkgs.vimPlugins.tokyonight-nvim}/extras/ghostty/tokyonight_night";
    };

    # Rex keeps imported themes in an opaque preference with generated IDs,
    # so a switch asks the running app to import Tokyo Night once and keep it
    # as the dark theme. It needs Remote Control, set below, and warns
    # instead of failing when the app is not running.
    activation.rexTheme = lib.hm.dag.entryAfter [ "writeBoundary" "setDarwinDefaults" ] ''
      run ${lib.getExe applyTheme} ${lib.escapeShellArg rexCli} \
        "$HOME/.config/rex/themes/tokyonight_night"
    '';
  };

  # Rex starts new terminals with the macOS login shell (zsh) unless its
  # Startup Command setting (Settings > Terminal) says otherwise. init.lua
  # cannot set it, so write the app preference directly. The profile path
  # stays valid across fish updates.
  targets.darwin.defaults."com.superlogical.rex" = {
    "Workspace.terminalStartupCommand" =
      "${config.home.profileDirectory}/bin/fish --login --interactive";
    # JetBrains Mono with Nerd Font icons, from the Homebrew cask in
    # modules/darwin/homebrew.nix, without ligatures, as Ghostty had it
    # (its default font with `font-feature = -calt/-liga/-dlig`).
    "Workspace.terminalFontName" = "JetBrainsMono Nerd Font";
    "Workspace.terminalAllowsLigatures" = false;
    # The size the Herdr app (../herdr-app/settings.json) and Ghostty (its
    # macOS default) use.
    "Workspace.terminalFontPointSize" = 13;
    # Remote Control (Settings > Server > Client Info) lets the `rex` CLI and
    # agents perform app actions, which the theme activation above uses.
    "rex.client.remoteControl" = true;
  };

  # The skill stub `rex skill setup` would install. It asks the installed CLI
  # for the guide at use time, so it follows Rex updates without changes here.
  agents.extraSkills.rex = ./skill;

  # What Rex's session-start hooks would tell an agent, as a shared rule in the
  # agent instruction files this repo renders. The rule keys off the
  # REX_SESSION and REX_BLOCK variables Rex sets in each pane, so it needs no
  # per-agent hook.
  agents.sharedRules.rex-terminal = ./agent-rule.md;
}
