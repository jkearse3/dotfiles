# The launch step every agent launcher (`claude`, `pi`, `opencode` and their
# `nono-` variants) ends with, kept in one place so all six run their agent the
# same way.
{ lib, pkgs }:
let
  # caffeinate's `-i` assertion keeps the machine from idle-sleeping for as long
  # as the agent runs; elsewhere the agent runs directly.
  preventIdleSleep = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "/usr/bin/caffeinate -i ";
in
# Returns the shell text that ends a launcher by running `commandLine`, the
# agent's already-quoted command and arguments, under the idle-sleep assertion.
# The text replaces the launcher process, so the agent's exit status is the
# launcher's.
{ commandLine }:
"exec ${preventIdleSleep}${commandLine}"
