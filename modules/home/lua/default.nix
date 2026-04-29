{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.lua-language-server
    pkgs.stylua
  ];
}
