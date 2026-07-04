{
  config,
  lib,
  ...
}:
let
  renderAgentsMarkdown = import ./renderAgentsMarkdown.nix { inherit lib; };
in
{
  imports = [
    ./registries.nix
    ./claude
    ./opencode
  ];

  config = {
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
    };
  };
}
