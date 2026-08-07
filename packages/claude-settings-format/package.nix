{
  pkgs,
}:
pkgs.writeShellApplication {
  name = "claude-settings-format";
  runtimeInputs = [
    pkgs.jq
  ];
  text = builtins.readFile ./claude-settings-format.sh;
}
