{
  internalPkgs,
  ...
}:

{
  home.packages = [ internalPkgs.playwright-cli ];
  agents.extraSkills."playwright-cli" = ./skill;
}
