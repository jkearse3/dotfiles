{
  config,
  ...
}:
{
  # Rex reads its keybindings from this file. Rex itself is installed as a
  # macOS app outside Nix, so this module only manages its config.
  home.file.".config/rex/init.lua".source = ./init.lua;

  # Rex starts new terminals with the macOS login shell (zsh) unless its
  # Startup Command setting (Settings > Terminal) says otherwise. init.lua
  # cannot set it, so write the app preference directly. The profile path
  # stays valid across fish updates.
  targets.darwin.defaults."com.superlogical.rex"."Workspace.terminalStartupCommand" =
    "${config.home.profileDirectory}/bin/fish --login --interactive";
}
