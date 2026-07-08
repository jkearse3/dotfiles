{
  jj-bookmark-nearest,
  pkgs,
}:
pkgs.writeShellApplication {
  name = "jj-bookmark-default";
  runtimeInputs = [
    jj-bookmark-nearest
  ];
  text = builtins.readFile ./jj-bookmark-default.sh;
}
