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
          unstablePkgs.nvd
          unstablePkgs.perl
          unstablePkgs.secretspec
          unstablePkgs.shellcheck
          unstablePkgs.statix
        ];
      };
    };
}
