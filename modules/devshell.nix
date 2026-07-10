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
          unstablePkgs.deadnix
          unstablePkgs.statix
        ];
      };
    };
}
