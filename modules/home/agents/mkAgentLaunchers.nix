# Builds an agent's two launchers: `launcher`, named `name`, which runs
# `command` directly, and `nonoLauncher`, named `nono-${name}`, which runs it
# inside the `coding-agents` nono profile.
#
# Each launcher applies the agent interactive policy, then hands off to
# `agentLauncher` (idle-sleep assertion and private temp root), then resolves
# the named secret environment, then enters nono when sandboxed, and finally
# runs the agent with the launcher's arguments. Caffeinate stays outermost so
# its idle-sleep assertion covers the whole session. Secret resolution stays
# inside it but outside nono so the sandbox never needs access to the machine's
# provider.
#
# `secretEnvironment` names the environment passed to
# `mkSecretEnvironmentWrapper` and has no default, so a caller that forgets it
# fails evaluation instead of launching without secrets.
{
  lib,
  pkgs,
  agentInteractivePolicy,
  agentLauncher,
  mkNonoWrapper,
  mkSecretEnvironmentWrapper,
}:
{
  name,
  command,
  secretEnvironment,
}:
let
  entrypoint = mkNonoWrapper {
    name = "${name}-entrypoint";
    profile = "coding-agents";
    inherit command;
  };

  mkLauncher =
    launcherName: agentCommand:
    let
      secret = mkSecretEnvironmentWrapper {
        name = "${launcherName}-secret-environment";
        environmentName = secretEnvironment;
        command = agentCommand;
      };
    in
    pkgs.writeShellApplication {
      name = launcherName;
      # Apply the non-interactive policy to the secret wrapper, nono, the agent,
      # and every command the agent runs without changing the user's
      # interactive shell.
      text = ''
        ${agentInteractivePolicy.shellExports}
        ${agentLauncher { commandLine = ''${lib.getExe secret} "$@"''; }}
      '';
    };
in
{
  launcher = mkLauncher name command;

  # `mkNonoWrapper` builds with `runCommandLocal`, which sets no `mainProgram`,
  # so the entrypoint's binary is named explicitly rather than via `getExe`.
  nonoLauncher = mkLauncher "nono-${name}" "${entrypoint}/bin/nono-${name}-entrypoint";
}
