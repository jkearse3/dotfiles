# Registers repository packages against stable nixpkgs and constructs the
# unstable set used for selected package dependencies, development tools, and
# configuration outputs.
{
  inputs,
  ...
}:
{
  perSystem =
    {
      pkgs,
      system,
      unstablePkgs,
      ...
    }:
    {
      # `rec` lets package recipes explicitly inject sibling repository packages
      # instead of discovering them through the eventual flake output.
      packages = rec {
        claude-settings-format = pkgs.callPackage ../packages/claude-settings-format/package.nix { };
        commit-message = pkgs.callPackage ../packages/commit-message/package.nix { };
        direnv-worktree = pkgs.callPackage ../packages/direnv-worktree/package.nix {
          inherit (unstablePkgs) git;
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
        git-worktree-cd = pkgs.callPackage ../packages/git-worktree-cd/package.nix { };
        git-worktree-select = pkgs.callPackage ../packages/git-worktree-select/package.nix { };
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
        jj-ensure = pkgs.callPackage ../packages/jj-ensure/package.nix {
          inherit (unstablePkgs) jujutsu;
        };
        herdr-worktree-bootstrap = pkgs.callPackage ../packages/herdr-worktree-bootstrap/package.nix {
          inherit (inputs.llm-agents.packages.${system}) herdr;
          inherit jj-ensure;
        };
        jj-bookmark-land = pkgs.callPackage ../packages/jj-bookmark-land/package.nix {
          inherit (unstablePkgs) jujutsu;
        };
        jj-description-format = pkgs.callPackage ../packages/jj-description-format/package.nix {
          inherit commit-message;
          inherit (unstablePkgs) jujutsu;
        };
        jj-worktree-add = pkgs.callPackage ../packages/jj-worktree-add/package.nix {
          inherit jj-ensure;
          inherit (unstablePkgs) jujutsu;
        };
        nix-cleanup = pkgs.callPackage ../packages/nix-cleanup/package.nix { };
        nvim-pack-prune = pkgs.callPackage ../packages/nvim-pack-prune/package.nix { };
        playwright-cli = pkgs.callPackage ../packages/playwright-cli/package.nix { };
        port-listeners-kill = pkgs.callPackage ../packages/port-listeners-kill/package.nix {
          inherit port-listeners-list;
        };
        port-listeners-list = pkgs.callPackage ../packages/port-listeners-list/package.nix { };
        token-count = pkgs.callPackage ../packages/token-count/package.nix { };
      };

      # flake-parts makes this argument available to dev-shell and configuration
      # constructors through `perSystem` and `withSystem`, respectively. These
      # overlays affect that unstable boundary only, not the stable `pkgs` above.
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
