# Source helper for home-manager file delivery.
#
# In editable mode, returns an out-of-store symlink rooted at the configured
# repository directory so working-tree edits take effect without rebuilding.
#
# In locked mode (`editable = false`), returns the input Nix path unchanged so
# home-manager performs its default copy-into-store delivery — safe to
# restructure the working tree under without dangling symlinks.
#
# Absolute paths outside the flake source (e.g. `${pkg}/share/foo` from
# another flake input) pass through unchanged regardless of mode, since
# there is no working tree to symlink into. Relative or non-absolute
# inputs throw, catching typos at eval time.
#
# Pass a Nix path value (e.g. `./settings.json`) or an interpolated store
# path; the helper either derives the repo-relative location by stripping the
# flake-root prefix (editable, in-flake), or hands the path back for store
# import.
#
# `dotfilesSource` identifies the source root, its home-relative checkout
# directory, and whether Home Manager should use editable delivery.
{
  config,
  dotfilesSource,
  lib,
}:
let
  repoBase = "${config.home.homeDirectory}/${dotfilesSource.repositoryDirectory}";
  sourceRoot = toString dotfilesSource.root;
in
path:
let
  pathStr = toString path;
in
if lib.hasPrefix "${sourceRoot}/" pathStr then
  if dotfilesSource.editable then
    config.lib.file.mkOutOfStoreSymlink "${repoBase}/${lib.removePrefix "${sourceRoot}/" pathStr}"
  else
    path
else if lib.hasPrefix "/" pathStr then
  path
else
  throw "mkSource: ${pathStr} must be an absolute path"
