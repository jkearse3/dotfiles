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
    let
      # The pi module delivers this directory to pi; the packages below build
      # its npm dependencies and check its sources.
      piExtensions = ../modules/home/agents/pi/extensions;
    in
    {
      # `rec` lets package recipes explicitly inject sibling repository packages
      # instead of discovering them through the eventual flake output.
      packages = rec {
        agent-interactive-denied = pkgs.callPackage ../packages/agent-interactive-denied/package.nix { };
        commit-message = pkgs.callPackage ../packages/commit-message/package.nix { };
        direnv-worktree = pkgs.callPackage ../packages/direnv-worktree/package.nix {
          inherit (unstablePkgs) git;
        };
        jjx = pkgs.callPackage ../packages/jjx/package.nix {
          inherit commit-message;
          inherit (unstablePkgs) jujutsu;
        };
        pi-shepherd = pkgs.callPackage ../packages/pi-shepherd/package.nix {
          inherit (inputs.llm-agents.packages.${system}) herdr;
        };
        herdr-worktree-bootstrap = pkgs.callPackage ../packages/herdr-worktree-bootstrap/package.nix {
          inherit (inputs.llm-agents.packages.${system}) herdr;
          inherit jjx;
        };
        nix-cleanup = pkgs.callPackage ../packages/nix-cleanup/package.nix { };
        nvim-pack = pkgs.callPackage ../packages/nvim-pack/package.nix {
          inherit (unstablePkgs) neovim;
        };
        pi-extension-deps = pkgs.callPackage ../packages/pi-extension-deps/package.nix {
          inherit (unstablePkgs) nodejs;
          extensions = piExtensions;
        };
        # The types must come from the same pi the home modules install, so this
        # takes the llm-agents package rather than the nixpkgs pi-coding-agent.
        pi-extension-types = pkgs.callPackage ../packages/pi-extension-types/package.nix {
          inherit (inputs.llm-agents.packages.${system}) pi;
          inherit (unstablePkgs) nodejs;
        };
        pi-extensions-checked = pkgs.callPackage ../packages/pi-extensions-checked/package.nix {
          inherit (inputs.llm-agents.packages.${system}) pi;
          inherit pi-extension-deps pi-extension-types;
          inherit (unstablePkgs) nodejs;
          extensions = piExtensions;
          # The 5.x compiler the extensions are written against; the unstable
          # default is the TypeScript 7 native preview.
          typescript = unstablePkgs.typescript_5;
        };
        playwright-cli = pkgs.callPackage ../packages/playwright-cli/package.nix { };
        ports = pkgs.callPackage ../packages/ports/package.nix { };
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
            inputs.nix-index-database.overlays.nix-index
            (import ./overlays/moreutils.nix)
            (import ./overlays/tokscale.nix)
          ];
        };
      };
    };
}
