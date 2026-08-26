{
  config,
  dotfilesPackages,
  lib,
  pkgs,
  ...
}:
let
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
    home.packages = [ dotfilesPackages.token-count ];

    home.file = {
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
}
