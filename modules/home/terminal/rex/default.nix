{
  config,
  dotfilesPackages,
  lib,
  pkgs,
  ...
}:
let
  # Rex installs itself outside Nix, and its updater replaces the CLI under
  # `Versions/Current`, so this path stays valid across Rex updates.
  rexCli = "${config.home.homeDirectory}/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex";

  # Puts `rex` on PATH outside Rex terminals too, for the skill below, which
  # calls bare `rex`, and for `rex-agents`.
  #
  # Also ships fish completion for `rex`. Rex lives outside the Nix store,
  # so the build cannot generate the script; instead fish autoloads this
  # file the first time it completes `rex` and sources what the installed
  # CLI generates, which keeps completion in step with Rex updates. Without
  # Rex installed the file does nothing.
  rexWrapper = pkgs.symlinkJoin {
    name = "rex";
    paths = [
      (pkgs.writeShellScriptBin "rex" ''
        exec ${lib.escapeShellArg rexCli} "$@"
      '')
      (pkgs.writeTextDir "share/fish/vendor_completions.d/rex.fish" ''
        if test -x ${lib.escapeShellArg rexCli}
            ${lib.escapeShellArg rexCli} --autostart=false completion fish | source
        end
      '')
    ];
  };

  # `packages/rex-agents` with this module's `rex` on its PATH, since the
  # package cannot know where Rex is installed.
  rexAgents = pkgs.symlinkJoin {
    name = "rex-agents";
    paths = [ dotfilesPackages.rex-agents ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/rex-agents" --prefix PATH : ${lib.makeBinPath [ rexWrapper ]}
    '';
  };

  applyTheme = pkgs.writeShellApplication {
    name = "rex-apply-theme";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = builtins.readFile ./apply-theme.sh;
  };

  # Hosts known to have the xterm-rex entry, one per line, which
  # `rex terminfo host` records; the ssh guard below sends them xterm-rex.
  terminfoHosts = "${config.home.homeDirectory}/.config/rex/terminfo-hosts";
in
{
  home = {
    packages = [
      rexWrapper
      rexAgents
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

      # The ssh guard `rex terminfo setup` writes, verbatim so Rex sees it
      # as current, at the path Rex looks for it. A Rex terminal claims
      # TERM=xterm-rex only once ssh would announce xterm-256color instead
      # to hosts without that entry, since a host without it cannot run
      # curses programs. Outside a Rex terminal the Match does nothing.
      # Rex's setup cannot add the Include line itself because Home Manager
      # owns ~/.ssh/config, so programs.ssh adds it.
      ".config/rex/ssh_config".text = ''
        # Written by "rex terminfo setup". Rex owns this file and rewrites it, so
        # edits made here are lost. Remove it with "rex terminfo remove".
        #
        # Rex terminals may set TERM=xterm-rex. A host that has no terminfo entry by
        # that name cannot run curses programs at all, so announce xterm-256color to
        # every host except the ones recorded in
        # ${terminfoHosts}
        # as having the entry. Outside a Rex terminal this block does nothing.

        Match exec "/bin/sh -c '[ x$TERM = xxterm-rex ] && ! grep -qxF -- %h ${terminfoHosts} 2>/dev/null'"
            SetEnv TERM=xterm-256color
      '';
    };

    # Rex keeps imported themes in an opaque preference with generated IDs,
    # so a switch asks the running app to import Tokyo Night once and keep it
    # as the dark theme. It needs Remote Control, set below, and warns
    # instead of failing when the app is not running.
    activation.rexTheme = lib.hm.dag.entryAfter [ "writeBoundary" "setDarwinDefaults" ] ''
      run ${lib.getExe applyTheme} ${lib.escapeShellArg rexCli} \
        "$HOME/.config/rex/themes/tokyonight_night"
    '';

    # Installs Rex's terminfo entry, xterm-rex, in ~/.terminfo from the
    # installed Rex, so it follows Rex updates. The entry is Ghostty's,
    # describing what Rex terminals support beyond xterm-256color, such as
    # styled underlines and synchronized output.
    activation.rexTerminfo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -x ${lib.escapeShellArg rexCli} ]; then
        run ${lib.escapeShellArg rexCli} --autostart=false terminfo setup --entry-only >/dev/null ||
          warnEcho "rex terminfo: could not install the xterm-rex entry"
      else
        warnEcho "rex terminfo: Rex is not installed; xterm-rex was not installed"
      fi
    '';
  };

  # SetEnv keeps the first value ssh parses, so the guard comes before every
  # other block.
  programs.ssh.includes = [ "${config.home.homeDirectory}/.config/rex/ssh_config" ];

  # Rex starts new terminals with the macOS login shell, which stays zsh until
  # switch-system makes it fish, unless its Startup Command setting
  # (Settings > Terminal) says otherwise. init.lua
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
    # The tab sidebar on the left of the window, as set on this machine.
    # init.lua cannot set it and Rex offers no app action for it, so it is
    # written as an app preference like the settings above.
    "Workspace.sidebarPosition" = "left";
    # Remote Control (Settings > Server > Client Info) lets the `rex` CLI and
    # agents perform app actions, which the theme activation above uses.
    "rex.client.remoteControl" = true;
  };

  # The skill stub `rex skill setup` would install. It asks the installed CLI
  # for the guide at use time, so it follows Rex updates without changes here.
  agents.extraSkills.rex = ./skill;

  # How agents carry out the Agent Terminals rule (`../agent-terminals.md`) in
  # Rex, as a shared rule in the agent instruction files this repo renders. It
  # has agents start, watch, resume, and release their helper agents with
  # `rex-agents`, and leaves jobs and servers to the `rex` skill's guide,
  # stating only where the workflow departs from it. `README.md` records
  # the Rex behavior it relies on. The rule keys off the REX_BLOCK variable Rex
  # sets in each pane, so it needs no per-agent hook.
  agents.sharedRules.rex-terminal = ./agent-rule.md;
}
