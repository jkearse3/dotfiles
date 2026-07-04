# Render composed skills into one directory source for a `home.file` entry.
{
  lib,
  pkgs,
  skills,
}:
{
  exclude ? [ ],
}:
let
  unavailable = builtins.filter (name: !(builtins.hasAttr name skills)) exclude;
  selected = lib.subtractLists exclude (builtins.attrNames skills);
  links = map (name: {
    inherit name;
    path = skills.${name};
  }) selected;
in
assert lib.assertMsg (
  unavailable == [ ]
) "Excluded unavailable agent skill(s): ${lib.concatStringsSep ", " unavailable}";
{
  source = pkgs.linkFarm "agent-skills" links;
  recursive = true;
}
