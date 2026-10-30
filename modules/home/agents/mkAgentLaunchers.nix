# Builds an agent's two launchers: `launcher`, named `name`, which runs
# `command` directly, and `nonoLauncher`, named `nono-${name}`, which runs it
# inside the `coding-agents` nono profile. Each agent module calls this once and
# declares only how its launch differs from the shared order below.
#
# Each launcher runs `setup`, applies the agent interactive policy, then hands
# off to `agentLauncher` (idle-sleep assertion and private temp root), then
# resolves the named secret environment, then enters nono when sandboxed, and
# finally runs the agent with `extraArguments` followed by the launcher's
# arguments. Caffeinate stays outermost so its idle-sleep assertion covers the
# whole session. Secret resolution stays inside it but outside nono so the
# sandbox never needs access to the machine's provider.
#
# Inputs:
#
# - `secretEnvironment` names the environment passed to
#   `mkSecretEnvironmentWrapper`. It has no default, so a caller that forgets
#   it fails evaluation instead of launching without secrets. `null` means the
#   agent takes no secrets: the launcher runs the agent without a secret
#   wrapper.
# - `setup` is shell text run first, before the policy exports, for work such
#   as computing values that `extraArguments` refers to. Default: none.
# - `extraArguments` is already-quoted shell text placed between the agent
#   command and the launcher's own arguments, so a caller's explicit flag
#   still comes later. Default: none.
# - `extraTmpdirVariables` names further variables `agentLauncher` points at the
#   private temp root, such as an agent's own temp-dir override. Default: none.
# - `runtimeInputs` are packages put on the launcher's PATH for `setup`. The
#   agent inherits that PATH, so these also reach the agent and every command
#   it runs. Default: none.
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
  setup ? "",
  extraArguments ? "",
  extraTmpdirVariables ? [ ],
  runtimeInputs ? [ ],
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
      innerCommand =
        if secretEnvironment == null then
          agentCommand
        else
          lib.getExe (mkSecretEnvironmentWrapper {
            name = "${launcherName}-secret-environment";
            environmentName = secretEnvironment;
            command = agentCommand;
          });

      commandLine = "${innerCommand}${
        lib.optionalString (extraArguments != "") " ${extraArguments}"
      } \"$@\"";

      # Only a non-empty list is passed, so an agent without extra variables
      # calls `agentLauncher` with `commandLine` alone. The secret-wrapper
      # test's `agentLauncher` stub accepts nothing else, which keeps checking
      # that Pi and OpenCode pass no extra variables.
      agentLauncherArguments = {
        inherit commandLine;
      }
      // lib.optionalAttrs (extraTmpdirVariables != [ ]) { inherit extraTmpdirVariables; };
    in
    pkgs.writeShellApplication {
      name = launcherName;
      inherit runtimeInputs;
      # Apply the non-interactive policy to the secret wrapper, nono, the agent,
      # and every command the agent runs without changing the user's
      # interactive shell.
      text = lib.optionalString (setup != "") "${setup}\n" + ''
        ${agentInteractivePolicy.shellExports}
        ${agentLauncher agentLauncherArguments}
      '';
    };
in
{
  launcher = mkLauncher name command;

  # `mkNonoWrapper` builds with `runCommandLocal`, which sets no `mainProgram`,
  # so the entrypoint's binary is named explicitly rather than via `getExe`.
  nonoLauncher = mkLauncher "nono-${name}" "${entrypoint}/bin/nono-${name}-entrypoint";
}
