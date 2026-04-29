# Source helper for home-manager file delivery.
#
# In editable mode (`editable = true`), returns an out-of-store symlink rooted
# at ~/<repoRoot> so working-tree edits take effect without rebuilding.
#
# In locked mode (`editable = false`), returns the input Nix path unchanged so
# home-manager performs its default copy-into-store delivery — safe to
# restructure the working tree under without dangling symlinks.
#
# Pass a Nix path value (e.g. `./settings.json`); the helper either derives
# the repo-relative location by stripping the flake-root prefix (editable),
# or hands the path back for store import (locked).
#
# Inputs:
#   editable — when true, deliver via out-of-store symlink to the working
#              tree; when false, deliver via in-store copy.
#   repoRoot — home-relative clone directory name (used in editable mode).
#
# Usage:
#   let mkSource = import ../mkSource.nix { inherit config self lib repoRoot editable; };
#   in { home.file.".config/nvim".source = mkSource ./nvim; }
{
  config,
  self,
  lib,
  repoRoot,
  editable,
}:
let
  repoBase = "${config.home.homeDirectory}/${repoRoot}";
  flakeSource = toString self;
in
path:
let
  pathStr = toString path;
in
if lib.hasPrefix "${flakeSource}/" pathStr then
  if editable then
    config.lib.file.mkOutOfStoreSymlink "${repoBase}/${lib.removePrefix "${flakeSource}/" pathStr}"
  else
    path
else
  throw "mkSource: path ${pathStr} is not within flake source ${flakeSource}"
