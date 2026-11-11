# `dotfiles-paths.json`, which maps program names for the mods to absolute
# store paths.
{
  dotfilesPackages,
  jujutsu,
  pkgs,
  spaceNew,
}:
# The launcher mods (`find`, `jj-workspace-new`, `jj-workspace-pick`,
# `jj-workspace-remove`, `space-new`) start their CLIs, and `desk-spaces` and
# `space-rename-all` run local spaces' `jj`, by the absolute store paths this
# file maps program names to, which `cliPath` in `mod-lib/paths.ts` reads. A
# bare name would resolve on the PATH of whichever process runs it: the core
# for the launchers' `hc run`, the app for those two mods' `exec`. Each PATH
# depends on how that process was started. Read-only, because it holds store
# paths.
(pkgs.formats.json { }).generate "herdr-app-dotfiles-paths.json" {
  herdr-find = "${dotfilesPackages.herdr-find.cli}/bin/herdr-find";
  herdr-jj-workspace = "${dotfilesPackages.herdr-jj-workspaces.cli}/bin/herdr-jj-workspace";
  herdr-space-new = "${spaceNew}";
  jj = "${jujutsu}/bin/jj";
}
