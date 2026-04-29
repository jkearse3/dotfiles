{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.bash-language-server
    pkgs.shellcheck
    pkgs.shfmt
  ];
}
