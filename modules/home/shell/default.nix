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

  programs = {
    direnv.enable = true;
    fzf.enable = true;
    zoxide.enable = true;
  };

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
