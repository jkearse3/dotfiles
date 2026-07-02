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
  renderRuleRegistries = import ./renderRuleRegistries.nix { inherit lib mkSource; };
in
{
  imports = [
    ./registries.nix
    ./claude
    ./opencode
  ];

  config = {
    home.file =
      renderRuleRegistries ".agents/rules" [
        {
          name = "shared";
          sources = config.agents.sharedRules;
        }
      ]
      // renderSharedSkills ".agents/skills" config.agents.sharedSkills;
  };
}
