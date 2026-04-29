{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "jj-bookmark-previous";
  runtimeInputs = [
    (pkgs.callPackage ../jj-bookmark-stacked/package.nix { })
  ];
  text = builtins.readFile ./jj-bookmark-previous.sh;
}
