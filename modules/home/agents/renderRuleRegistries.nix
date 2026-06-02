# Render rule registries into a single parent directory.
#
# Given a `home.file` prefix (e.g. `.agents/rules`, `.claude/rules`, or
# `.config/opencode/rules`) and a list of named registries, produces a
# `home.file` attrset whose keys are `<prefix>/<name>.md` and whose sources are
# built via `mkSource`. Agent modules pass the shared registry plus their own
# per-agent registry so each target gets the right flat rule set without relying
# on loader-specific directory traversal.
#
# This helper validates the contracts that only exist once registries are
# combined for a target:
#   - the same rendered rule name cannot come from multiple registries;
#   - every source path must end in `.md`, matching the rendered filename.
#
# Inputs:
#   lib       - nixpkgs lib (for list/attrset transforms).
#   mkSource  - source helper from `modules/home/mkSource.nix`, already
#               instantiated with the caller's `config`/`self`/`editable` so
#               this helper does not need to thread those arguments.
#
# Usage:
#   let
#     renderRuleRegistries = import ./renderRuleRegistries.nix { inherit lib mkSource; };
#   in {
#     home.file = renderRuleRegistries ".claude/rules" [
#       { name = "shared"; sources = config.agents.sharedRules; }
#       { name = "claude"; sources = config.agents.claudeRules; }
#     ];
#   }
{
  lib,
  mkSource,
}:
prefix: registries:
let
  flattenRegistry =
    registry:
    map (name: {
      inherit name;
      registryName = registry.name;
      src = registry.sources.${name};
    }) (lib.attrNames registry.sources);

  entries = lib.concatMap flattenRegistry registries;

  collisions = lib.filterAttrs (_: matches: lib.length matches > 1) (
    lib.groupBy (entry: entry.name) entries
  );
  collisionMessages = lib.mapAttrsToList (
    name: matches:
    "renderRuleRegistries: name '${name}' is defined in registries '${
      lib.concatStringsSep "' and '" (map (entry: entry.registryName) matches)
    }'"
  ) collisions;

  checkedSource =
    entry:
    let
      sourcePath = toString entry.src;
    in
    if lib.hasSuffix ".md" sourcePath then
      entry.src
    else
      throw "renderRuleRegistries: source for rule '${entry.name}' in registry '${entry.registryName}' must end in .md: ${sourcePath}";
in
if collisionMessages != [ ] then
  throw (lib.concatStringsSep "; " collisionMessages)
else
  builtins.listToAttrs (
    map (entry: {
      name = "${prefix}/${entry.name}.md";
      value.source = mkSource (checkedSource entry);
    }) entries
  )
