{
  pkgs,
  ...
}:
{
  imports = [
    ./fish
    ./port-listeners-list
    ./port-listeners-kill
    ./starship
    ./zsh
  ];

  programs.direnv.enable = true;
  programs.fzf.enable = true;
  programs.zoxide.enable = true;

  home.packages = [
    pkgs.bottom
    pkgs.curl
    pkgs.difftastic
    pkgs.dua
    pkgs.eza
    pkgs.fd
    pkgs.hexyl
    pkgs.htop
    pkgs.jless
    pkgs.jq
    pkgs.ripgrep
    pkgs.tokei
    pkgs.wget
  ];
}
