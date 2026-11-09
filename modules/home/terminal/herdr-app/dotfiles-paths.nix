# `dotfiles-paths.json`, which maps the launcher mods' CLI names to absolute
# store paths.
{
  dotfilesPackages,
  pkgs,
  spaceNew,
}:
# The launcher mods (`find`, `jj-workspace-new`, `jj-workspace-pick`,
# `jj-workspace-remove`, `space-new`) start their CLIs by the absolute store
# paths this file maps CLI names to, which `cliPath` in `mod-lib/paths.js`
# reads. A bare name would resolve on the core's
# PATH, which depends on whoever started the core. Read-only, because it
# holds store paths.
(pkgs.formats.json { }).generate "herdr-app-dotfiles-paths.json" {
  herdr-find = "${dotfilesPackages.herdr-find.cli}/bin/herdr-find";
  herdr-jj-workspace = "${dotfilesPackages.herdr-jj-workspaces.cli}/bin/herdr-jj-workspace";
  herdr-space-new = "${spaceNew}";
}
