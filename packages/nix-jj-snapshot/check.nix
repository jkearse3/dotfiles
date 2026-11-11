# Runs `behavior-test.sh` against a wrapper whose real Nix is a stub that logs
# its arguments and its HOME, so the test never runs Nix or jj.
{
  lib,
  pkgs,
  runCommand,
  writeShellScript,
}:
let
  realNixStub = writeShellScript "real-nix-stub" ''
    {
      printf 'nix'
      printf ' [%s]' "$@"
      printf '\n'
    } >>"$NIX_JJ_SNAPSHOT_TEST_LOG"
    printf '%s\n' "''${HOME-<unset>}" >"$NIX_JJ_SNAPSHOT_TEST_LOG.home"
    echo "real nix output"
  '';
  wrapper = pkgs.callPackage ./package.nix { realNix = "${realNixStub}"; };
in
runCommand "nix-jj-snapshot-behavior" { } ''
  bash ${./behavior-test.sh} ${lib.getExe wrapper}
  touch "$out"
''
