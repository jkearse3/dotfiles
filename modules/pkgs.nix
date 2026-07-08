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
      packages = rec {
        commit-message-check = pkgs.callPackage ../packages/commit-message-check/package.nix { };
        jj-change-select = pkgs.callPackage ../packages/jj-change-select/package.nix { };
        jj-bookmark-nearest = pkgs.callPackage ../packages/jj-bookmark-nearest/package.nix { };
        jj-bookmark-current = pkgs.callPackage ../packages/jj-bookmark-current/package.nix {
          inherit jj-bookmark-nearest;
        };
        jj-bookmark-default = pkgs.callPackage ../packages/jj-bookmark-default/package.nix {
          inherit jj-bookmark-nearest;
        };
        jj-bookmark-stacked = pkgs.callPackage ../packages/jj-bookmark-stacked/package.nix {
          inherit jj-bookmark-default;
        };
        jj-bookmark-previous = pkgs.callPackage ../packages/jj-bookmark-previous/package.nix {
          inherit jj-bookmark-stacked;
        };
        jj-bookmark-select = pkgs.callPackage ../packages/jj-bookmark-select/package.nix { };
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
