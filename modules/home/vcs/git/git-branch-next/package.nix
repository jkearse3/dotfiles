{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "git-branch-next";
  runtimeInputs = [
    pkgs.git
    (pkgs.callPackage ../git-branch-current/package.nix { })
  ];
  text = builtins.readFile ./git-branch-next.sh;
}
