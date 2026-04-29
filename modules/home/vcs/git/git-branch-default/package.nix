{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "git-branch-default";
  runtimeInputs = [
    pkgs.git
  ];
  text = builtins.readFile ./git-branch-default.sh;
}
