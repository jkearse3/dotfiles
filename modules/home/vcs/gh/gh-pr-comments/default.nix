{
  internalPkgs,
  pkgs,
  ...
}:
{
  home.packages = [
    (pkgs.callPackage ./package.nix { inherit (internalPkgs) jj-bookmark-current; })
  ];
}
