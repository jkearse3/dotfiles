{
  config,
  pkgs,
  ...
}:
let
  # Rex installs itself outside Nix, and its updater replaces the CLI under
  # `Versions/Current`, so this path stays valid across Rex updates.
  rexCli = "${config.home.homeDirectory}/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex";
in
{
  # Puts `rex` on PATH outside Rex terminals too, for the skill below, which
  # calls bare `rex`.
  home.packages = [
    (pkgs.writeShellScriptBin "rex" ''
      exec ${pkgs.lib.escapeShellArg rexCli} "$@"
    '')
  ];

  # Rex reads its keybindings from this file. Rex itself is installed as a
  # macOS app outside Nix, so this module only manages its config.
  home.file.".config/rex/init.lua".source = ./init.lua;

  # Rex starts new terminals with the macOS login shell (zsh) unless its
  # Startup Command setting (Settings > Terminal) says otherwise. init.lua
  # cannot set it, so write the app preference directly. The profile path
  # stays valid across fish updates.
  targets.darwin.defaults."com.superlogical.rex"."Workspace.terminalStartupCommand" =
    "${config.home.profileDirectory}/bin/fish --login --interactive";

  # The skill stub `rex skill setup` would install. It asks the installed CLI
  # for the guide at use time, so it follows Rex updates without changes here.
  agents.extraSkills.rex = ./skill;

  # What Rex's session-start hooks would tell an agent, as a shared rule in the
  # agent instruction files this repo renders. The rule keys off the
  # REX_SESSION and REX_BLOCK variables Rex sets in each pane, so it needs no
  # per-agent hook.
  agents.sharedRules.rex-terminal = ./agent-rule.md;
}
