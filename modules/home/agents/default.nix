{
  config,
  lib,
  ...
}:
let
  renderSharedSkills = import ./renderSharedSkills.nix { inherit lib; };
  renderAgentsMarkdown = import ./renderAgentsMarkdown.nix { inherit lib; };
in
{
  imports = [
    ./registries.nix
    ./claude
    ./opencode
  ];

  config = {
    home.file = renderSharedSkills ".agents/skills" config.agents.sharedSkills // {
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
    };
  };
}
