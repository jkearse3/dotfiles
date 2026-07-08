{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "jj-bookmark-nearest";
  runtimeInputs = [
    pkgs.jujutsu
  ];
  text = builtins.readFile ./jj-bookmark-nearest.sh;
}
