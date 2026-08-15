# Builds a launcher that runs `command` with a named secret environment's
# variables already present in its process. Callers name only the logical
# environment; which provider resolves it, and how, is owned by this module.
#
# The backend is SecretSpec: the committed secretspec.toml declares what may be
# resolved, while each machine maps the project-specific `dotfiles` provider
# alias to a concrete provider. No secret value or provider choice lives here.
{
  lib,
  pkgs,
  environments,
  manifest,
}:
{
  name,
  environmentName,
  command,
}:
assert lib.assertMsg (name != "") "mkSecretEnvironmentWrapper: name must not be empty";
assert lib.assertMsg (command != "") "mkSecretEnvironmentWrapper: command must not be empty";
assert lib.assertMsg (lib.elem environmentName environments)
  "mkSecretEnvironmentWrapper: unknown secret environment '${environmentName}'; declare it in modules/home/secrets";
let
  escapedCommand = lib.escapeShellArg command;
  escapedScope = lib.escapeShellArg environmentName;

  # The manifest is a value-free registry, so shipping it into the store is safe.
  # Pinning a store path also stops SecretSpec's current-directory discovery from
  # selecting another repository's secretspec.toml when a launcher runs there.
  manifestPath = builtins.path {
    path = manifest;
    name = "secretspec.toml";
  };
in
pkgs.writeShellApplication {
  inherit name;
  runtimeInputs = [
    pkgs.secretspec
    pkgs.gnugrep
  ];
  text = ''
    manifest=${lib.escapeShellArg "${manifestPath}"}

    # SECRETSPEC_PROVIDER is the intentional per-invocation override. Without it,
    # resolve through the machine-local `dotfiles` alias. That alias must be
    # registered first; an unregistered alias means an uncommissioned machine, so
    # fail with actionable guidance rather than launch without declared secrets.
    # Only the fallback route is preflighted: an explicit provider, and any
    # malformed or failing registered provider, remain SecretSpec's concern.
    provider="''${SECRETSPEC_PROVIDER:-dotfiles}"
    if [ -z "''${SECRETSPEC_PROVIDER:-}" ]; then
      if ! secretspec config global provider list 2>/dev/null \
        | grep -qE '^[[:space:]]*dotfiles[[:space:]]*='; then
        {
          echo "secretspec: this machine is not commissioned for the \"dotfiles\" secret provider."
          echo "Map the dotfiles alias to a provider on this machine, then retry:"
          echo
          echo "  secretspec config global provider add dotfiles <provider>   # e.g. keyring://, pass://, gopass://"
          echo "  secretspec config global provider list"
          echo
          echo "See ~/dotfiles/docs/secrets.md for provider choices and setup."
        } >&2
        exit 1
      fi
    fi

    # Explicit --file/--profile/--scope override any ambient SECRETSPEC_* env, so
    # a launcher's contract does not shift with the caller's shell. The target
    # keeps its own argv after `--`; no shell string is reconstructed.
    exec secretspec run \
      --file "$manifest" \
      --provider "$provider" \
      --profile default \
      --scope ${escapedScope} \
      -- ${escapedCommand} "$@"
  '';
}
