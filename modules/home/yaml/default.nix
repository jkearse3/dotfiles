{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.yaml-language-server
    pkgs.yq
  ];
}
