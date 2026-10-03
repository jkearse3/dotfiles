{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "ports";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.findutils
    pkgs.fzf
    pkgs.gawk
    pkgs.lsof
  ];
  text = builtins.readFile ./ports.sh;
}
