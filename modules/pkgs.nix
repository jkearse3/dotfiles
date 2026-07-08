{
  inputs,
  ...
}:
{
  perSystem =
    {
      pkgs,
      system,
      ...
    }:
    {
      packages = {
        playwright-cli = pkgs.callPackage ../packages/playwright-cli/package.nix { };
      };

      _module.args = {
        unstablePkgs = import inputs.nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            (import inputs.rust-overlay)
            (import ./overlays/direnv.nix)
          ];
        };
      };
    };
}
