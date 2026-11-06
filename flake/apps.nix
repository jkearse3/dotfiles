# Registers the flake apps that build and switch the selected blueprint and
# update dependencies: `nix run .#<app> -- [options]` from the repository root.
# Each app runs the `dotfiles-apps` script (`packages/dotfiles-apps`) with its
# own name as the command. The script is a flake check rather than a package,
# so `nix flake check` runs its shellcheck, and `dotfiles-apps-arguments` tests
# its argument and blueprint-selection errors, the arguments package-update
# passes to the package updaters, and which checks flake-update runs before it
# commits, using stub `nix` and `jj` commands.
{
  config,
  lib,
  ...
}:
let
  blueprintIds = builtins.attrNames config.flake.blueprints;
in
{
  perSystem =
    {
      pkgs,
      unstablePkgs,
      ...
    }:
    let
      dotfilesApps = pkgs.callPackage ../packages/dotfiles-apps/package.nix {
        inherit (unstablePkgs) nh nix-output-monitor;
        inherit (config.flake) blueprints;
      };

      mkDotfilesApp = command: description: {
        program = pkgs.writeShellScriptBin command ''
          exec ${lib.getExe dotfilesApps} ${command} "$@"
        '';
        meta.description = description;
      };
    in
    {
      apps = {
        build-home = mkDotfilesApp "build-home" "Build the selected blueprint's Home Manager configuration and diff it";
        switch-home = mkDotfilesApp "switch-home" "Build and activate the selected blueprint's Home Manager configuration";
        build-system = mkDotfilesApp "build-system" "Build the selected blueprint's nix-darwin configuration and diff it";
        switch-system = mkDotfilesApp "switch-system" "Build and activate the selected blueprint's nix-darwin configuration";
        package-update = mkDotfilesApp "package-update" "Pin every package with an updater to its latest upstream release";
        flake-update = mkDotfilesApp "flake-update" "Update flake inputs and package pins, check the flake, build the selected blueprint's Home Manager configuration, and commit with jj";
      };

      checks = {
        dotfiles-apps = dotfilesApps;
        dotfiles-apps-arguments = pkgs.runCommand "dotfiles-apps-arguments" { } ''
          bash ${../packages/dotfiles-apps/arguments-test.sh} ${lib.getExe dotfilesApps} ${lib.escapeShellArg (builtins.head blueprintIds)}
          touch "$out"
        '';
      };
    };
}
