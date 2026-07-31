{
  dotfilesPackages,
  ...
}:
{
  imports = [ ../agents/registries.nix ];

  home.packages = [ dotfilesPackages.playwright-cli ];
  agents.extraSkills."playwright-cli" = ./skill;
}
