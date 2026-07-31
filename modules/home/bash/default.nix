{
  dotfilesPackages,
  pkgs,
  ...
}:
{
  programs.bash = {
    enable = true;
    initExtra = ''
      source ${dotfilesPackages.git-worktree-cd.shellInit.bash}
    '';
  };

  home.packages = [
    pkgs.bash-language-server
    pkgs.shellcheck
    pkgs.shfmt
  ];
}
