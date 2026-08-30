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
  renderAgentsMarkdown = import ./renderAgentsMarkdown.nix { inherit lib; };
  renderSkillsDir = import ./renderSkillsDir.nix {
    inherit lib pkgs;
    skills = config.agents.skills;
  };
in
{
  imports = [
    ./registries.nix
    ./claude
    ./codex
    ./opencode
    ./pi
  ];

  config = {
    _module.args.agentInteractivePolicy = agentInteractivePolicy;

    home = {
      packages = [
        dotfilesPackages.agent-interactive-denied
        dotfilesPackages.token-count
      ];

      extraBuilderCommands = ''
        mkdir -p $out/state
        ln -s ${agentInteractivePolicy.check} $out/state/agent-interactive-policy-checked
      '';

      file = {
        ".codex/AGENTS.md".text = renderAgentsMarkdown {
          title = "Codex Instructions";
          registries = [
            {
              name = "shared";
              sources = config.agents.sharedRules;
            }
          ];
          order = config.agents.sharedRuleOrder;
        };
        ".agents/mcp.json".source = ./mcp.json;
        ".agents/skills" = renderSkillsDir { };
      };
    };
  };
}
