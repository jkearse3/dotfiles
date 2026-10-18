{
  config,
  dotfilesPackages,
  lib,
  pkgs,
  ...
}:
let
  agentInteractivePolicy = import ./interactive-policy.nix {
    inherit lib pkgs;
    agentInteractiveDenied = dotfilesPackages.agent-interactive-denied;
  };
  agentLauncher = import ./launcher.nix { inherit lib pkgs; };
  renderSkillsDir = import ./renderSkillsDir.nix {
    inherit lib pkgs;
    skills = config.agents.skills;
  };
in
{
  imports = [
    ./registries.nix
    ./shell.nix
    ./claude
    ./opencode
    ./pi
  ];

  config = {
    _module.args = {
      inherit agentInteractivePolicy agentLauncher;
    };

    home = {
      packages = [
        dotfilesPackages.agent-interactive-denied
        dotfilesPackages.scratch-sweep
        dotfilesPackages.token-count
        pkgs.tokscale
      ];

      extraBuilderCommands = ''
        mkdir -p $out/state
        ln -s ${agentInteractivePolicy.check} $out/state/agent-interactive-policy-checked
      '';

      file = {
        ".agents/mcp.json".source = ./mcp.json;
        ".agents/skills" = renderSkillsDir { };
      };
    };
  };
}
