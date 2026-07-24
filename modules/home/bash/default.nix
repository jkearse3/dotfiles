{
  internalPkgs,
  pkgs,
  ...
}:
{
  programs.bash = {
    enable = true;
    initExtra = ''
      source ${internalPkgs.git-worktree-cd.shellInit.bash}
    '';
  };

  home.packages = [
    pkgs.bash-language-server
    pkgs.shellcheck
    pkgs.shfmt
  ];
}
