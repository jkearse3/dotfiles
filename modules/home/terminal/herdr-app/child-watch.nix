# The `hc-child-watch` command: prints one line per change in a parent
# terminal's agent children, for agents that learn of their children without
# hc typing into their input box (`child-watch.sh`).
{
  herdrCore,
  pkgs,
}:
let
  childWatch = pkgs.writeShellApplication {
    name = "hc-child-watch";
    runtimeInputs = [
      herdrCore
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
    ];
    text = builtins.readFile ./child-watch.sh;
  };
in
# Installed through this path, so failing fixtures fail the build. They run
# the script itself, because the command's PATH would put the real `hc`
# ahead of their fake one.
pkgs.runCommandLocal "hc-child-watch-checked" { } ''
  bash ${./child-watch-test.sh} ${./child-watch.sh} ${pkgs.jq}/bin/jq
  ln -s ${childWatch} "$out"
''
