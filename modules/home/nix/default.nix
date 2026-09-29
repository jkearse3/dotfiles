{
  dotfilesPackages,
  pkgs,
  ...
}:
{
  # The nix-index-database overlay wraps nix-locate and comma with a prebuilt
  # database, so neither needs a local `nix-index` run or a cache symlink.
  home.packages = [
    dotfilesPackages.nix-cleanup
    pkgs.comma-with-db
    pkgs.deadnix
    pkgs.devenv
    pkgs.nix-index-with-db
    pkgs.nix-output-monitor
    pkgs.nixd
    pkgs.nixfmt
    pkgs.nvd
    pkgs.statix
  ];
}
