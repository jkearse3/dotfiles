{
  dotfilesPackages,
  ...
}:
{
  imports = [ ../agents/skills.nix ];

  home.packages = [ dotfilesPackages.playwright-cli ];
  agents.extraSkills."playwright-cli" = ./skill;
}
