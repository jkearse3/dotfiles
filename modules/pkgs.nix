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
        commit-message-format = pkgs.callPackage ../packages/commit-message-format/package.nix {
          inherit commit-message-check;
        };
        git-branch-checkout = pkgs.callPackage ../packages/git-branch-checkout/package.nix { };
        git-branch-current = pkgs.callPackage ../packages/git-branch-current/package.nix { };
        git-branch-default = pkgs.callPackage ../packages/git-branch-default/package.nix { };
        git-branch-delete = pkgs.callPackage ../packages/git-branch-delete/package.nix { };
        git-branch-next = pkgs.callPackage ../packages/git-branch-next/package.nix {
          inherit git-branch-current;
        };
        git-branch-previous = pkgs.callPackage ../packages/git-branch-previous/package.nix {
          inherit git-branch-stacked;
        };
        git-branch-stacked = pkgs.callPackage ../packages/git-branch-stacked/package.nix {
          inherit git-branch-default;
        };
        gh-pr-comments = pkgs.callPackage ../packages/gh-pr-comments/package.nix {
          inherit jj-bookmark-current;
        };
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
        nix-cleanup = pkgs.callPackage ../packages/nix-cleanup/package.nix { };
        playwright-cli = pkgs.callPackage ../packages/playwright-cli/package.nix { };
        port-listeners-kill = pkgs.callPackage ../packages/port-listeners-kill/package.nix {
          inherit port-listeners-list;
        };
        port-listeners-list = pkgs.callPackage ../packages/port-listeners-list/package.nix { };
        token-count = pkgs.callPackage ../packages/token-count/package.nix { };
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
