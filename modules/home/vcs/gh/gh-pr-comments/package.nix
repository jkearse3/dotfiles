{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "gh-pr-comments";
  runtimeInputs = [
    (pkgs.callPackage ../../jj/jj-bookmark-current/package.nix { })
    pkgs.gh
  ];
  text = builtins.readFile ./gh-pr-comments.sh;
}
