{
  jj-bookmark-default,
  pkgs,
}:
pkgs.writeShellApplication {
  name = "jj-bookmark-stacked";
  runtimeInputs = [
    pkgs.jujutsu
    jj-bookmark-default
  ];
  text = builtins.readFile ./jj-bookmark-stacked.sh;
}
