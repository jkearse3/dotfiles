{
  jj-bookmark-stacked,
  pkgs,
}:
pkgs.writeShellApplication {
  name = "jj-bookmark-previous";
  runtimeInputs = [
    jj-bookmark-stacked
  ];
  text = builtins.readFile ./jj-bookmark-previous.sh;
}
