{
  jj-bookmark-nearest,
  pkgs,
}:
pkgs.writeShellApplication {
  name = "jj-bookmark-current";
  runtimeInputs = [
    jj-bookmark-nearest
  ];
  text = builtins.readFile ./jj-bookmark-current.sh;
}
