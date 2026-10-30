# Pure manifest-policy tests fail during evaluation, before this check builds.
# No SecretSpec process, credentials, or machine-local configuration is involved.
{ lib, runCommand }:
let
  failures = import ./manifest-policy.nix { inherit lib; };
in
assert lib.assertMsg (failures == [ ]) "manifest-policy tests failed: ${builtins.toJSON failures}";
runCommand "manifest-policy" { } ''
  touch "$out"
''
