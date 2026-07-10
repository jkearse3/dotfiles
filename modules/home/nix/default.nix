{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.deadnix
    pkgs.devenv
    pkgs.nix-output-monitor
    pkgs.nixd
    pkgs.nixfmt
    pkgs.nvd
    pkgs.statix
  ];
}
