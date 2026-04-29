{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "jj-change-select";
  runtimeInputs = [
    pkgs.jujutsu
    pkgs.fzf
  ];
  text = builtins.readFile ./jj-change-select.sh;
}
