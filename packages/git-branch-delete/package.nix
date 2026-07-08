{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "git-branch-delete";
  runtimeInputs = [
    pkgs.git
    pkgs.fzf
  ];
  text = builtins.readFile ./git-branch-delete.sh;
}
