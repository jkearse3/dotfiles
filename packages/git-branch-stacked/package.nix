{
  git-branch-default,
  pkgs,
}:
pkgs.writeShellApplication {
  name = "git-branch-stacked";
  runtimeInputs = [
    pkgs.git
    git-branch-default
  ];
  text = builtins.readFile ./git-branch-stacked.sh;
}
