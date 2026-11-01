# The script behind this repository's flake apps, which `flake/apps.nix`
# registers: it builds and switches the selected blueprint's Home Manager and
# nix-darwin configurations through nh, and updates the flake inputs and package
# pins. `blueprints` is the flake's `blueprints` inventory, compiled into the
# script's `blueprint_output` function at build time so blueprint selection
# needs no Nix evaluation. `nix` and `jj` come from the user's PATH: the system
# `nix` talks to its own daemon, and `flake-update` must commit with the jj
# version that manages the repository.
{
  pkgs,
  nh,
  nix-output-monitor,
  blueprints,
}:
let
  inherit (pkgs.lib)
    concatLists
    concatStringsSep
    escapeShellArg
    mapAttrsToList
    ;

  # One `case` branch per blueprint and kind of output.
  blueprintOutputCases = concatStringsSep "\n  " (
    concatLists (
      mapAttrsToList (blueprintId: blueprint: [
        "home:${escapeShellArg blueprintId}) echo ${escapeShellArg blueprint.homeConfigurationName} ;;"
        "system:${escapeShellArg blueprintId}) echo ${escapeShellArg blueprint.darwinConfigurationName} ;;"
      ]) blueprints
    )
  );
in
pkgs.writeShellApplication {
  name = "dotfiles-apps";
  runtimeInputs = [
    # Package updaters run through `#!/usr/bin/env bash`, need Bash 5, and
    # compute and edit their pins with coreutils, grep, jq, sed, and perl.
    pkgs.bash
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.jq
    pkgs.perl
    # nh builds, diffs, and activates the Home Manager and nix-darwin
    # configurations, and shows build progress through nix-output-monitor.
    nh
    nix-output-monitor
  ];
  text = ''
    # Prints the flake output that a blueprint's `home` or `system` apps build:
    # `blueprint_output <home|system> <blueprint-id>`. Fails for an ID the
    # inventory lacks.
    blueprint_output() {
      case $1:$2 in
      ${blueprintOutputCases}
      *) return 1 ;;
      esac
    }
  ''
  + builtins.readFile ./dotfiles-apps.sh;
}
