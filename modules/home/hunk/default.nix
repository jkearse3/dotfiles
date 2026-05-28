{
  hunk,
  ...
}:
{
  home.packages = [ hunk ];
  agents.sharedSkills."hunk-review" = [ "${hunk.outPath}/skills/hunk-review" ];
}
