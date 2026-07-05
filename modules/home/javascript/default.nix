{ config, pkgs, ... }:
{
  home.packages = [
    pkgs.bun
    pkgs.eslint
    pkgs.nodejs
    pkgs.prettier
    pkgs.typescript-language-server
  ];
  home.sessionPath = [
    "${config.home.homeDirectory}/.npm-global/bin"
  ];
  home.file.".npmrc".text = # ini
    ''
      cache=${config.home.homeDirectory}/.cache/npm
      prefix=${config.home.homeDirectory}/.npm-global
    '';
}
