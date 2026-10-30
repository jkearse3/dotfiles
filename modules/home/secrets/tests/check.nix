# Pure policy tests and isolated executions of the actual generated launchers.
{
  lib,
  runCommand,
  pkgs,
  test ? "manifest-policy",
}:
let
  failures = import ./manifest-policy.nix { inherit lib; };
  manifest = pkgs.writeText "wrapper-test.toml" ''
    [project]
    name = "wrapper-test"
    revision = "1.0"
    require_reason = false
    [profiles.default]
    ADMITTED = { description = "Local fixture", required = false }
    EXCLUDED = { description = "Local fixture", required = false }
    [profiles.other]
    OTHER_PROFILE = { description = "Local fixture", required = false }
    [scopes.optional]
    secrets = ["ADMITTED"]
  '';
  stub = pkgs.writeShellApplication {
    name = "secretspec";
    text = ''
      if [ "$1" = config ]; then
        printf '%s\n' "''${PROVIDER_LIST:-}"
        exit "''${INSPECT_STATUS:-0}"
      fi
      printf '%s\n' "$@" > "$TEST_ROOT/selectors"
      exit "''${PROVIDER_STATUS:-37}"
    '';
  };
  child = pkgs.writeShellScript "wrapper-child" ''
    printf '%s\n' started > "$TEST_ROOT/started"
    env > "$TEST_ROOT/environment"
    printf '%s\0' "$@" > "$TEST_ROOT/argv"
    exit "''${CHILD_STATUS:-0}"
  '';
  wrapper =
    secretspec: allowMissingProvider:
    import ../mkSecretEnvironmentWrapper.nix
      {
        inherit lib manifest;
        pkgs = pkgs // {
          inherit secretspec;
        };
        environments = [ "optional" ];
      }
      {
        name = "secret-wrapper";
        environmentName = "optional";
        command = "${child}";
        inherit allowMissingProvider;
      };
in
if test == "manifest-policy" then
  assert lib.assertMsg (failures == [ ]) "manifest-policy tests failed: ${builtins.toJSON failures}";
  runCommand "manifest-policy" { } ''
    touch "$out"
  ''
else
  runCommand "secret-wrappers"
    {
      nativeBuildInputs = [
        pkgs.bash
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.secretspec
      ];
      OPTIONAL_WRAPPER = "${wrapper stub true}/bin/secret-wrapper";
      REQUIRED_WRAPPER = "${wrapper stub false}/bin/secret-wrapper";
      REAL_WRAPPER = "${wrapper pkgs.secretspec true}/bin/secret-wrapper";
      TEST_MANIFEST = manifest;
    }
    ''
      # Start from an empty environment, including all SECRETSPEC_* variables.
      env -i PATH="$PATH" TEST_ROOT="$TMPDIR/stub" \
        OPTIONAL_WRAPPER="$OPTIONAL_WRAPPER" REQUIRED_WRAPPER="$REQUIRED_WRAPPER" \
        bash ${./wrapper-test.sh}
      env -i PATH="$PATH" TEST_ROOT="$TMPDIR/real" \
        REAL_WRAPPER="$REAL_WRAPPER" TEST_MANIFEST="$TEST_MANIFEST" \
        bash ${./secretspec-integration-test.sh}
      touch "$out"
    ''
