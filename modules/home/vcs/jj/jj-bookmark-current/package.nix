{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "jj-bookmark-current";
  runtimeInputs = [
    (pkgs.callPackage ../jj-bookmark-nearest/package.nix { })
  ];
  text = builtins.readFile ./jj-bookmark-current.sh;
}
