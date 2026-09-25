{
  pkgs,
  ...
}:
{
  programs.bash.enable = true;

  home.packages = [
    pkgs.bash-language-server
    pkgs.shellcheck
    pkgs.shfmt
  ];
}
