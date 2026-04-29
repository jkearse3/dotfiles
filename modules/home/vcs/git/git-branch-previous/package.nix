{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "git-branch-previous";
  runtimeInputs = [
    (pkgs.callPackage ../git-branch-stacked/package.nix { })
  ];
  text = builtins.readFile ./git-branch-previous.sh;
}
