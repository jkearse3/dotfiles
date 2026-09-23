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

  # The GNU core utilities shadow the macOS BSD tools in `/usr/bin` for every
  # shell that loads the profile, so humans and agents share one set of flags.
  # BSD `tar` stays: it also extracts zip archives and preserves macOS extended
  # attributes, which GNU tar does not.
  home.packages = [
    pkgs.bottom
    pkgs.coreutils
    pkgs.curl
    pkgs.difftastic
    pkgs.dua
    pkgs.eza
    pkgs.fd
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.hexyl
    pkgs.htop
    pkgs.jless
    pkgs.jq
    pkgs.ripgrep
    pkgs.tokei
    pkgs.wget
  ];
}
