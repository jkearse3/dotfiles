{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "jj-bookmark-select";
  runtimeInputs = [
    pkgs.jujutsu
    pkgs.fzf
  ];
  text = builtins.readFile ./jj-bookmark-select.sh;
}
