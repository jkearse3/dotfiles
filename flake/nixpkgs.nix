# Constructs the shared unstable nixpkgs set used for selected repository
# package dependencies, the development shell, and configuration constructors.
# Stable `pkgs` is flake-parts' default from `inputs.nixpkgs` and is not
# configured here.
{
  inputs,
  ...
}:
{
  perSystem =
    {
      system,
      ...
    }:
    {
      # flake-parts makes this argument available to dev-shell and configuration
      # constructors through `perSystem` and `withSystem`, respectively. These
      # overlays affect that unstable boundary only, not the stable `pkgs`.
      _module.args = {
        unstablePkgs = import inputs.nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            (import inputs.rust-overlay)
            inputs.nix-index-database.overlays.nix-index
            (import ../overlays/moreutils.nix)
            (import ../overlays/nix-output-monitor.nix)
            (import ../overlays/tokscale.nix)
          ];
        };
      };
    };
}
