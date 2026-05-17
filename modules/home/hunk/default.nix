{
  hunk,
  ...
}:
{
  home.packages = [ hunk ];
  agents.skillSources."hunk-review" = "${hunk.outPath}/skills/hunk-review";
}
