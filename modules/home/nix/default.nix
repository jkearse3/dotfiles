{
  internalPkgs,
  pkgs,
  ...
}:
{
  home.packages = [
    internalPkgs.nix-cleanup
    pkgs.deadnix
    pkgs.devenv
    pkgs.nix-output-monitor
    pkgs.nixd
    pkgs.nixfmt
    pkgs.nvd
    pkgs.statix
  ];
}
