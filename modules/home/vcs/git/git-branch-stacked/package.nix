{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "git-branch-stacked";
  runtimeInputs = [
    pkgs.git
    (pkgs.callPackage ../git-branch-default/package.nix { })
  ];
  text = builtins.readFile ./git-branch-stacked.sh;
}
