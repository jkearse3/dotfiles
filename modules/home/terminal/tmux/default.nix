{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.tmux
  ];
  home.file = {
    ".config/tmux/tmux.conf".source = ./tmux.conf;
    ".config/tmux/plugins/resurrect".source =
      "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect";
  };
}
