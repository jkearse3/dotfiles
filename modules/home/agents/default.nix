{
  config,
  lib,
  self,
  repoRoot,
  editable,
  ...
}:
let
  mkSource = import ../mkSource.nix {
    inherit
      config
      self
      lib
      repoRoot
      editable
      ;
  };
  renderSharedSkills = import ./renderSharedSkills.nix { inherit lib mkSource; };
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
