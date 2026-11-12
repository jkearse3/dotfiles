# Registers repository packages against stable nixpkgs, taking selected
# dependencies from the shared unstable set that `flake/nixpkgs.nix` constructs.
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
      # its npm dependencies, check its sources, and assemble its locked tree.
      piExtensions = ../modules/home/agents/pi/extensions;

      # The personal herdr-app mods, the shared code they link to, and the
      # project config that type-checks them, laid out as in
      # `modules/home/terminal/herdr-app` so the mods' relative links to
      # `../../mod-lib` resolve.
      herdrAppModSources = pkgs.lib.fileset.toSource {
        root = ../modules/home/terminal/herdr-app;
        fileset = pkgs.lib.fileset.unions [
          ../modules/home/terminal/herdr-app/mods
          ../modules/home/terminal/herdr-app/mod-lib
          ../modules/home/terminal/herdr-app/tsconfig.json
        ];
      };
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
          inherit commit-message direnv-worktree worktree-include;
          inherit (unstablePkgs) jujutsu;
        };
        herdr-app = inputs.llm-agents.packages.${system}.herdr-app;
        herdr-app-mod-types = pkgs.callPackage ../packages/herdr-app-mod-types/package.nix {
          inherit herdr-app;
        };
        herdr-app-mods = pkgs.callPackage ../packages/herdr-app-mods/package.nix {
          inherit herdr-app herdr-app-mod-types;
          inherit (unstablePkgs) typescript;
          nodejs = unstablePkgs.nodejs_24;
          modSources = herdrAppModSources;
        };
        herdr-core = pkgs.callPackage ../packages/herdr-core/package.nix {
          upstream = inputs.llm-agents.packages.${system}.herdr-core;
        };
        herdr-find = pkgs.callPackage ../packages/herdr-find/package.nix {
          inherit (inputs.llm-agents.packages.${system}) herdr;
          inherit herdr-app herdr-core;
        };
        herdr-jj-workspaces = pkgs.callPackage ../packages/herdr-jj-workspaces/package.nix {
          inherit (inputs.llm-agents.packages.${system}) herdr;
          inherit herdr-app herdr-core jjx;
          inherit (unstablePkgs) jujutsu;
        };
        herdr-worktree-bootstrap = pkgs.callPackage ../packages/herdr-worktree-bootstrap/package.nix {
          inherit (inputs.llm-agents.packages.${system}) herdr;
          inherit jjx;
        };
        nix-cleanup = pkgs.callPackage ../packages/nix-cleanup/package.nix { };
        nix-jj-snapshot = pkgs.callPackage ../packages/nix-jj-snapshot/package.nix { };
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
          inherit (inputs.llm-agents.packages.${system}) herdr pi;
          inherit pi-extension-deps pi-extension-types;
          inherit (unstablePkgs) nodejs typescript;
          extensions = piExtensions;
        };
        pi-extensions-locked = pkgs.callPackage ../packages/pi-extensions-locked/package.nix {
          inherit pi-extension-deps pi-extensions-checked;
          extensions = piExtensions;
        };
        playwright-cli = pkgs.callPackage ../packages/playwright-cli/package.nix { };
        ports = pkgs.callPackage ../packages/ports/package.nix { };
        scratch-sweep = pkgs.callPackage ../packages/scratch-sweep/package.nix { };
        token-count = pkgs.callPackage ../packages/token-count/package.nix { };
        worktree-include = pkgs.callPackage ../packages/worktree-include/package.nix {
          inherit (unstablePkgs) git;
        };
      };
    };
}
