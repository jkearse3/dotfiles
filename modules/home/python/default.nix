{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.basedpyright
    pkgs.python3
    pkgs.ruff
  ];
}
