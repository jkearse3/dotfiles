{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "port-listeners-kill";
  runtimeInputs = [
    pkgs.fzf
    pkgs.gawk
    (pkgs.callPackage ../port-listeners-list/package.nix { })
  ];
  text = builtins.readFile ./port-listeners-kill.sh;
}
