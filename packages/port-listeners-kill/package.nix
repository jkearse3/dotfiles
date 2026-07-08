{
  pkgs,
  port-listeners-list,
}:
pkgs.writeShellApplication {
  name = "port-listeners-kill";
  runtimeInputs = [
    pkgs.fzf
    pkgs.gawk
    port-listeners-list
  ];
  text = builtins.readFile ./port-listeners-kill.sh;
}
