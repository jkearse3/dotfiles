{
  hunk,
  ...
}:
{
  home.packages = [ hunk ];
  agents.extraSkills."hunk-review" = "${hunk.outPath}/skills/hunk-review";
}
