{
  git-branch-current,
  pkgs,
}:
pkgs.writeShellApplication {
  name = "git-branch-next";
  runtimeInputs = [
    pkgs.git
    git-branch-current
  ];
  text = builtins.readFile ./git-branch-next.sh;
}
