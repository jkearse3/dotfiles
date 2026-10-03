{
  perSystem =
    {
      config,
      unstablePkgs,
      ...
    }:
    {
      devShells.default = unstablePkgs.mkShell {
        packages = [
          config.treefmt.build.wrapper
          config.packages.commit-message
          config.packages.jjx

          unstablePkgs.bash
          unstablePkgs.pyrefly
          unstablePkgs.coreutils
          unstablePkgs.deadnix
          unstablePkgs.git
          unstablePkgs.gnugrep
          unstablePkgs.gnused
          unstablePkgs.jq
          unstablePkgs.jujutsu
          unstablePkgs.nodejs
          unstablePkgs.nvd
          unstablePkgs.perl
          unstablePkgs.secretspec
          unstablePkgs.shellcheck
          unstablePkgs.statix
        ];

        # Editors resolve pi's modules through this link, which the extensions'
        # `tsconfig.json` extends. It is per-checkout: work happens in worktrees
        # under ~/.herdr/worktrees, so a `home.file` entry would serve the main
        # checkout alone. Runtime npm dependencies remain an ordinary, gitignored
        # `node_modules`; this separate link cannot be confused with packages npm
        # owns. The link is replaced whenever the shell starts so a Pi version
        # bump cannot leave editors pinned to stale declarations.
        shellHook = ''
          piRepoRoot="$(${unstablePkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null || true)"
          if [ -z "$piRepoRoot" ]; then
            echo "devshell: pi extension types not linked; not inside a git worktree" >&2
          elif [ ! -d "$piRepoRoot/modules/home/agents/pi/extensions" ]; then
            echo "devshell: pi extension types not linked; $piRepoRoot/modules/home/agents/pi/extensions is missing" >&2
          else
            piExtensionTypes="$piRepoRoot/modules/home/agents/pi/extensions/.pi-types"
            if [ -d "$piExtensionTypes" ] && [ ! -L "$piExtensionTypes" ]; then
              rm -rf "$piExtensionTypes"
            fi
            ln -sfn ${config.packages.pi-extension-types} "$piExtensionTypes"
            unset piExtensionTypes
          fi
          unset piRepoRoot
        '';
      };
    };
}
