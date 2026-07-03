{ lib }:
{
  title ? "Generated Agent Instructions",
  registries,
  order,
}:
let
  flattenRegistry =
    registry:
    map (
      name:
      let
        id = "${registry.name}/${name}";
      in
      {
        inherit id name;
        registryName = registry.name;
        src = registry.sources.${name};
      }
    ) (lib.attrNames registry.sources);

  entries = lib.concatMap flattenRegistry registries;
  entriesById = lib.groupBy (entry: entry.id) entries;

  collisions = lib.filterAttrs (_: matches: lib.length matches > 1) entriesById;
  collisionMessages = lib.mapAttrsToList (
    id: matches:
    "renderAgentsMarkdown: rule ID '${id}' is defined in registries '${
      lib.concatStringsSep "' and '" (map (entry: entry.registryName) matches)
    }'"
  ) collisions;

  missingIds = lib.filter (id: !(builtins.hasAttr id entriesById)) order;
  missingMessage =
    if missingIds == [ ] then
      null
    else
      "renderAgentsMarkdown: ordered rule ID(s) not found: ${lib.concatStringsSep ", " missingIds}";

  selectedEntries = map (id: lib.head entriesById.${id}) order;
in
if collisionMessages != [ ] then
  throw (lib.concatStringsSep "; " collisionMessages)
else if missingMessage != null then
  throw missingMessage
else
  lib.concatStringsSep "\n\n" (
    [ "# ${title}" ] ++ map (entry: builtins.readFile entry.src) selectedEntries
  )
  + "\n"
