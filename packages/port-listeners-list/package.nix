{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "port-listeners-list";
  runtimeInputs = [
    pkgs.gawk
    pkgs.lsof
  ];
  text = builtins.readFile ./port-listeners-list.sh;
}
