# Builds a launcher that runs `command` with a named secret environment's
# variables already present in its process. Callers name only the logical
# environment; which provider resolves it, and how, is owned by this module.
{
  lib,
  pkgs,
  environmentFiles,
}:
{
  name,
  environmentName,
  command,
}:
assert lib.assertMsg (name != "") "mkSecretEnvironmentWrapper: name must not be empty";
assert lib.assertMsg (command != "") "mkSecretEnvironmentWrapper: command must not be empty";
assert lib.assertMsg (environmentFiles ? ${environmentName})
  "mkSecretEnvironmentWrapper: unknown secret environment '${environmentName}'; declare it in modules/home/secrets";
let
  escapedCommand = lib.escapeShellArg command;

  # The environment file enters the store under a provider-stable name: SOPS
  # selects its input format from the file suffix.
  environmentFile =
    if environmentFiles.${environmentName} == null then
      null
    else
      builtins.path {
        path = environmentFiles.${environmentName};
        name = "${environmentName}-sops-environment.sops.yaml";
      };

  useSops = environmentFile != null;

  # An environment with no configured file is a pass-through: no provider runs
  # and nothing is injected, so hosts without secrets launch unchanged.
  passThroughScript = ''
    exec ${escapedCommand} "$@"
  '';

  # `sops exec-env` runs its command as a single shell string, so the target and
  # its arguments are re-quoted into one word-safe string first. `--same-process`
  # keeps the target as this process, preserving signals and exit status.
  sopsScript = ''
    printf -v command_string '%q ' ${escapedCommand} "$@"
    exec ${lib.getExe pkgs.sops} exec-env --same-process \
      ${environmentFile} "$command_string"
  '';

  # The generated script is fixed by construction, but the configured file is
  # caller-supplied: `builtins.path` copies whatever it is given, so a path
  # pointing at decrypted content would be shipped to a launcher as if it were
  # ciphertext. Fail the build instead. Injection itself needs key material the
  # build sandbox does not have, so decryption stays manual validation.
  verifyEnvironmentFile = {
    inherit environmentFile;
    nativeBuildInputs = [ pkgs.gnugrep ];
    postCheck = ''
      grep -q '^sops:' "$environmentFile" \
        || { echo "FAIL: ${environmentName} environment file has no SOPS metadata block" >&2; exit 1; }
    '';
  };
in
pkgs.writeShellApplication {
  inherit name;
  text = if useSops then sopsScript else passThroughScript;
  derivationArgs = lib.optionalAttrs useSops verifyEnvironmentFile;
}
