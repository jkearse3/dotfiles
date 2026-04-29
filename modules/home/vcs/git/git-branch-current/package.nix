{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "git-branch-current";
  runtimeInputs = [
    pkgs.git
  ];
  text = builtins.readFile ./git-branch-current.sh;
}
