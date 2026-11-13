# The script behind this repository's flake apps, which `flake/apps.nix`
# registers: it builds and switches the selected blueprint's Home Manager and
# nix-darwin configurations through nh, and updates the flake inputs and package
# pins. `blueprints` is the flake's `blueprints` inventory, compiled into the
# script's `blueprint_output` function at build time so blueprint selection
# needs no Nix evaluation. `git` and `commit-message` are pinned here, while
# `nix` and `jj` come from the user's PATH: the system `nix` talks to its own
# daemon, and `flake-update` must commit with the jj version that manages the
# repository.
{
  pkgs,
  nh,
  nix-output-monitor,
  commit-message,
  blueprints,
}:
let
  inherit (pkgs.lib)
    concatLists
    concatStringsSep
    escapeShellArg
    escapeShellArgs
    mapAttrsToList
    ;

  # The distinct target triples of a Nix system.
  platformTargets =
    system:
    let
      platform = pkgs.lib.systems.elaborate system;
    in
    pkgs.lib.unique [
      platform.config
      platform.rust.rustcTarget
    ];

  # One `case` branch per blueprint and kind of output. `platform-targets` lists
  # the target triples nixpkgs derives for the blueprint's system: its general
  # triple and Rust's, which differ on some systems (`arm64-apple-darwin` and
  # `aarch64-apple-darwin` for `aarch64-darwin`).
  blueprintOutputCases = concatStringsSep "\n  " (
    concatLists (
      mapAttrsToList (blueprintId: blueprint: [
        "home:${escapeShellArg blueprintId}) echo ${escapeShellArg blueprint.homeConfigurationName} ;;"
        "system:${escapeShellArg blueprintId}) echo ${escapeShellArg blueprint.darwinConfigurationName} ;;"
        "platform:${escapeShellArg blueprintId}) echo ${escapeShellArg blueprint.system} ;;"
        "platform-targets:${escapeShellArg blueprintId}) printf '%s\\n' ${escapeShellArgs (platformTargets blueprint.system)} ;;"
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
    # The switch apps ask git whether `.` is a linked worktree. jj's colocated
    # workspaces set extensions.relativeWorktrees, which needs git 2.48 or later.
    pkgs.git
    # flake-update wraps and validates the descriptions it generates.
    commit-message
  ];
  text = ''
    # Prints the flake output that a blueprint's `home` or `system` apps build:
    # `blueprint_output <home|system> <blueprint-id>`, or the blueprint's Nix
    # system (`platform`) or its target triples, one per line
    # (`platform-targets`). Fails for an ID the inventory lacks.
    blueprint_output() {
      case $1:$2 in
      ${blueprintOutputCases}
      *) return 1 ;;
      esac
    }
  ''
  + builtins.readFile ./flake-update.sh
  + builtins.readFile ./dotfiles-apps.sh;
}
