{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.age
    pkgs.sops
  ];
}
