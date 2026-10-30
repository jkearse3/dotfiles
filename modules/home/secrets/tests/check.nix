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
    EXCLUDED = { description = "Local fixture", required = true }
    [profiles.other]
    OTHER_PROFILE = { description = "Local fixture", required = false }
    [scopes.optional]
    secrets = ["ADMITTED"]
    [scopes.required]
    secrets = ["EXCLUDED"]
    [scopes.inactive]
    secrets = ["OTHER_PROFILE"]
  '';
  stub = pkgs.writeShellApplication {
    name = "secretspec";
    text = ''
      if [ "$1" = config ]; then
        if [ -n "''${CONSUMER_TRACE:-}" ]; then
          printf '%s\n' inspect >> "$CONSUMER_TRACE"
        fi
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
    secretspec: environmentName:
    import ../mkSecretEnvironmentWrapper.nix
      {
        inherit lib manifest;
        pkgs = pkgs // {
          inherit secretspec;
        };
      }
      {
        name = "secret-wrapper";
        inherit environmentName;
        command = "${child}";
      };
  consumers = import ./consumer-wrappers.nix { inherit lib pkgs stub; };
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
      OPTIONAL_WRAPPER = "${wrapper stub "optional"}/bin/secret-wrapper";
      REQUIRED_WRAPPER = "${wrapper stub "required"}/bin/secret-wrapper";
      REAL_WRAPPER = "${wrapper pkgs.secretspec "optional"}/bin/secret-wrapper";
      INACTIVE_WRAPPER = "${wrapper stub "inactive"}/bin/secret-wrapper";
      CONSUMER_WRAPPERS = lib.concatStringsSep " " consumers.optional;
      REQUIRED_CONSUMER_WRAPPERS = lib.concatStringsSep " " consumers.required;
      TEST_MANIFEST = manifest;
    }
    ''
      # Start from an empty environment, including all SECRETSPEC_* variables.
      env -i PATH="$PATH" TEST_ROOT="$TMPDIR/stub" \
        OPTIONAL_WRAPPER="$OPTIONAL_WRAPPER" REQUIRED_WRAPPER="$REQUIRED_WRAPPER" \
        INACTIVE_WRAPPER="$INACTIVE_WRAPPER" \
        bash ${./wrapper-test.sh}
      env -i PATH="$PATH" TEST_ROOT="$TMPDIR/real" \
        REAL_WRAPPER="$REAL_WRAPPER" TEST_MANIFEST="$TEST_MANIFEST" \
        bash ${./secretspec-integration-test.sh}
      env -i PATH="$PATH" TEST_ROOT="$TMPDIR/consumers" \
        CONSUMER_WRAPPERS="$CONSUMER_WRAPPERS" \
        REQUIRED_CONSUMER_WRAPPERS="$REQUIRED_CONSUMER_WRAPPERS" \
        bash ${./consumer-wrapper-test.sh}
      touch "$out"
    ''
