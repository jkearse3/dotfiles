# The personal mod folder names in `./mods` (`personalMods`) and every mod
# name the app will find installed (`modNames`), which the keys and layout
# checks validate against.
{
  herdrApp,
  lib,
  pkgs,
}:
let
  personalMods = lib.optionals (builtins.pathExists ./mods) (
    lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./mods))
  );
  # Every mod name the app will find installed, as a JSON array: the pinned
  # app's shipped mods and each folder in `./mods`.
  modNames =
    pkgs.runCommandLocal "herdr-app-mod-names.json" { nativeBuildInputs = [ pkgs.jq ]; } # bash
      ''
        find ${herdrApp.src}/defaults/mods -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
          | jq -Rn --argjson personal ${lib.escapeShellArg (builtins.toJSON personalMods)} '[inputs] + $personal' > $out
      '';
in
{
  inherit personalMods modNames;
}
