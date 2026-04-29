{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "jj-bookmark-default";
  runtimeInputs = [
    (pkgs.callPackage ../jj-bookmark-nearest/package.nix { })
  ];
  text = builtins.readFile ./jj-bookmark-default.sh;
}
