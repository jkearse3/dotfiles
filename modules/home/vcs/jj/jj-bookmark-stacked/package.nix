{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "jj-bookmark-stacked";
  runtimeInputs = [
    pkgs.jujutsu
    (pkgs.callPackage ../jj-bookmark-default/package.nix { })
  ];
  text = builtins.readFile ./jj-bookmark-stacked.sh;
}
