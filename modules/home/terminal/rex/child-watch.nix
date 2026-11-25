# The `rex-child-watch` command: prints one line per change in the agent
# children a parent Rex pane registers, for agents that learn of their
# children without anything typed into their input box (`child-watch.sh`).
{
  pkgs,
  rexWrapper,
}:
let
  childWatch = pkgs.writeShellApplication {
    name = "rex-child-watch";
    runtimeInputs = [
      rexWrapper
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
    ];
    text = builtins.readFile ./child-watch.sh;
  };
in
# Installed through this path, so failing fixtures fail the build. They run
# the script itself, because the command's PATH would put the real `rex`
# ahead of their fake one.
pkgs.runCommandLocal "rex-child-watch-checked" { } ''
  bash ${./child-watch-test.sh} ${./child-watch.sh} ${pkgs.jq}/bin/jq
  ln -s ${childWatch} "$out"
''
