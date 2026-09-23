{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.pyrefly
    pkgs.python3
    pkgs.ruff
  ];
}
