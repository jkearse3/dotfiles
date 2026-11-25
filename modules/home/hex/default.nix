{
  lib,
  pkgs,
  ...
}:
let
  # The Homebrew cask installs Hex here and updates it in place, so this path
  # stays valid across Hex updates.
  hexCli = "/Applications/Hex.app/Contents/MacOS/hex";

  applySettings = pkgs.writeShellApplication {
    name = "hex-apply-settings";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./apply-settings.sh;
  };
in
# Hex is a macOS app that modules/darwin/homebrew.nix installs, so there is
# nothing to configure on other platforms.
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  # Hex writes its own settings.json, from its window and when it migrates the
  # file's format, so a read-only link to the repository would break it.
  # Instead each switch applies the settings declared in ./settings.json and
  # leaves the rest to the app. A declared setting changed in the Hex window
  # reverts on the next switch, so change it here.
  #
  # ./settings.json holds the Global dictation mode, whose replacements fix
  # how Hex spells "Johnnie Kearse". ./vocabulary.json holds vocabulary terms,
  # which Hex accepts only while it runs.
  home.activation.hexSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe applySettings} ${lib.escapeShellArg hexCli} \
      ${./settings.json} ${./vocabulary.json}
  '';
}
