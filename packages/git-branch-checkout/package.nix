{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "git-branch-checkout";
  runtimeInputs = [
    pkgs.git
    pkgs.fzf
  ];
  text = builtins.readFile ./git-branch-checkout.sh;
}
