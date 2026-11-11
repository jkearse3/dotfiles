# Runs `names-test.mjs`, the tests of `mod-lib/names.ts`, with Node's test
# runner. The source holds only those two files, so editing other herdr-app
# files does not rebuild the check.
#
# `flake/checks.nix` registers this as the `herdr-app-names` check with
# `callPackage`.
{
  lib,
  nodejs,
  runCommand,
}:
let
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./names-test.mjs
      ./mod-lib/names.ts
    ];
  };
in
runCommand "herdr-app-names"
  {
    nativeBuildInputs = [ nodejs ];
  }
  ''
    node --test ${src}/names-test.mjs
    touch "$out"
  ''
