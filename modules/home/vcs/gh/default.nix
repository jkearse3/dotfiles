{
  pkgs,
  ...
}:
{
  imports = [
    ./gh-pr-comments
  ];
  home.packages = [
    pkgs.gh
  ];
}
