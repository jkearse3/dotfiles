{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "git-worktree-select";
  runtimeInputs = [
    pkgs.git
    pkgs.fzf
  ];
  text = builtins.readFile ./git-worktree-select.sh;
}
