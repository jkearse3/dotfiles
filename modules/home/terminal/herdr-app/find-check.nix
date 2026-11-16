# Runs `find-test.mjs`, the tests of the find mod's pure files, with Node's
# test runner. The tests import the built, type-stripped `find/*.js` from the
# herdr-app-mods output rather than the `.ts` sources, because the mod's
# `./status.js` and `./names.js` imports resolve only there, where the build
# has copied the linked `mod-lib` files in. `FZF` names the fzf the matching
# test runs for real.
#
# `flake/checks.nix` registers this as the `herdr-app-find` check with
# `callPackage`.
{
  fzf,
  herdrAppMods,
  lib,
  nodejs,
  runCommand,
}:
let
  src = lib.fileset.toSource {
    root = ./.;
    fileset = ./find-test.mjs;
  };
in
runCommand "herdr-app-find"
  {
    nativeBuildInputs = [ nodejs ];
  }
  ''
    HERDR_APP_MODS=${herdrAppMods} FZF=${fzf}/bin/fzf node --test ${src}/find-test.mjs
    touch "$out"
  ''
