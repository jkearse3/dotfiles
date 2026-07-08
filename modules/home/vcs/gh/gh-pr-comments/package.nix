{
  jj-bookmark-current,
  pkgs,
}:
pkgs.writeShellApplication {
  name = "gh-pr-comments";
  runtimeInputs = [
    jj-bookmark-current
    pkgs.gh
  ];
  text = builtins.readFile ./gh-pr-comments.sh;
}
