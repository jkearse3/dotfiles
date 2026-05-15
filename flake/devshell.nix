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
          config.packages.jj-ensure

          unstablePkgs.bash
          unstablePkgs.basedpyright
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
          unstablePkgs.typescript
        ];

        # Pi extension declarations are dev-only and per-checkout: work happens in
        # worktrees under ~/.herdr/worktrees, so a `home.file` entry would serve
        # the main checkout alone. `git rev-parse --show-toplevel` resolves the
        # worktree being edited, unlike $PWD, which is the repository root only
        # under direnv. The link is replaced every time so a pi version bump is
        # picked up rather than pinned by a stale symlink.
        shellHook = ''
          piRepoRoot="$(${unstablePkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null || true)"
          if [ -z "$piRepoRoot" ]; then
            echo "devshell: pi extension types not linked; not inside a git worktree" >&2
          elif [ ! -d "$piRepoRoot/modules/home/agents/pi/extensions" ]; then
            echo "devshell: pi extension types not linked; $piRepoRoot/modules/home/agents/pi/extensions is missing" >&2
          else
            # `ln -sfn` cannot replace a real directory, so clear one out of the
            # way first. Only a link belongs here; the tree is never installed
            # into the checkout.
            piExtensionDeps="$piRepoRoot/modules/home/agents/pi/extensions/node_modules"
            if [ -d "$piExtensionDeps" ] && [ ! -L "$piExtensionDeps" ]; then
              rm -rf "$piExtensionDeps"
            fi
            ln -sfn ${config.packages.pi-extension-types}/node_modules "$piExtensionDeps"
            unset piExtensionDeps
          fi
          unset piRepoRoot
        '';
      };
    };
}
