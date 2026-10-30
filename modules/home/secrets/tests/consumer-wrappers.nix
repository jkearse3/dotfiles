# Import the consumer modules themselves, replacing only external dependencies.
# Their launcher/secret/sandbox composition remains the production composition.
{
  lib,
  pkgs,
  stub,
}:
let
  child =
    name:
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        printf '%s\n' child >> "$CONSUMER_TRACE"
        env > "$TEST_ROOT/environment"
        printf '%s\0' "$@" > "$TEST_ROOT/argv"
        exit "''${CHILD_STATUS:-0}"
      '';
    };
  consumerPackages =
    manifest:
    let
      args = {
        inherit lib pkgs;
        config.agents = {
          shellPath = "${pkgs.bash}/bin/bash";
          pi.packages = [ ];
        };
        dotfilesPackages = {
          pi = child "pi";
          opencode = child "opencode";
        };
        dotfilesSource.editable = true;
        mkSource = path: path;
        agentInteractivePolicy.shellExports = "export TEST_INTERACTIVE_POLICY=applied";
        agentLauncher = { commandLine }: ''
          printf '%s\n' launcher >> "$CONSUMER_TRACE"
          exec ${commandLine}
        '';
        mkNonoWrapper =
          {
            name,
            command,
            profile,
          }:
          assert profile == "coding-agents";
          pkgs.writeShellApplication {
            name = "nono-${name}";
            text = ''
              printf '%s\n' sandbox >> "$CONSUMER_TRACE"
              if [ "''${EXCLUDED+x}" = x ]; then
                echo 'excluded secret reached sandbox' >&2
                exit 99
              fi
              exec ${lib.escapeShellArg command} "$@"
            '';
          };
        mkSecretEnvironmentWrapper = import ../mkSecretEnvironmentWrapper.nix {
          inherit lib manifest;
          pkgs = pkgs // {
            secretspec = stub;
          };
        };
      };
      pi = (import ../../agents/pi/default.nix args).config.home.packages;
      opencode = (import ../../agents/opencode/default.nix args).config.home.packages;
    in
    map lib.getExe (pi ++ opencode);
  repositoryManifest = ../../../../secretspec.toml;
  requiredManifest = pkgs.writeText "required-consumers.toml" (
    builtins.replaceStrings [ "required = false" ] [ "required = true" ] (
      builtins.readFile repositoryManifest
    )
  );
  # An extra profile declaration tests filtering before reaching the sandbox.
  withExcludedSecret =
    manifest:
    pkgs.writeText "consumer-test.toml" ''
      ${builtins.readFile manifest}
      [profiles.other]
      EXCLUDED = { required = true }
    '';
in
{
  optional = consumerPackages (withExcludedSecret repositoryManifest);
  required = consumerPackages (withExcludedSecret requiredManifest);
}
