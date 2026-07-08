{
  git-branch-stacked,
  pkgs,
}:
pkgs.writeShellApplication {
  name = "git-branch-previous";
  runtimeInputs = [
    git-branch-stacked
  ];
  text = builtins.readFile ./git-branch-previous.sh;
}
