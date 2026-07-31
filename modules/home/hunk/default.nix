{
  dotfilesPackages,
  ...
}:
{
  imports = [ ../agents/registries.nix ];

  home.packages = [ dotfilesPackages.hunk ];
  agents.extraSkills."hunk-review" = "${dotfilesPackages.hunk.outPath}/skills/hunk-review";
}
