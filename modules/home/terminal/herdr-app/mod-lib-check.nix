# Runs `mod-lib-test.mjs`, the tests of the mod-lib pure files the
# desk-spaces sidebar draws its tree with, with Node's test runner. The tests
# import the built, type-stripped `desk-spaces/*.js` from the herdr-app-mods
# output rather than the `mod-lib/*.ts` sources, because those files' `.js`
# imports of one another resolve only there, where the build has copied the
# linked `mod-lib` files in.
#
# `flake/checks.nix` registers this as the `herdr-app-mod-lib` check with
# `callPackage`.
{
  herdrAppMods,
  lib,
  nodejs,
  runCommand,
}:
let
  src = lib.fileset.toSource {
    root = ./.;
    fileset = ./mod-lib-test.mjs;
  };
in
runCommand "herdr-app-mod-lib"
  {
    nativeBuildInputs = [ nodejs ];
  }
  ''
    HERDR_APP_MODS=${herdrAppMods} node --test ${src}/mod-lib-test.mjs
    touch "$out"
  ''
