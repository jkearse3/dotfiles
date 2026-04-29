{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.devenv
    pkgs.nix-output-monitor
    pkgs.nixd
    pkgs.nixfmt
    pkgs.nvd
  ];
}
