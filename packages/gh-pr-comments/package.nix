{
  jjx,
  pkgs,
}:
pkgs.writeShellApplication {
  name = "gh-pr-comments";
  runtimeInputs = [
    jjx
    pkgs.gh
  ];
  text = builtins.readFile ./gh-pr-comments.sh;
}
