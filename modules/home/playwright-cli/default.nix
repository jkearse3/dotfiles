{
  pkgs,
  self,
  ...
}:

{
  home.packages = [ self.packages.${pkgs.system}.playwright-cli ];
  agents.extraSkills."playwright-cli" = ./skill;
}
