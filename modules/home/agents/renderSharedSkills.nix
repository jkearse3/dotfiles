# Render the shared-skills registry into a single parent directory.
#
# Given a `home.file` prefix (e.g. `.agents/skills` or `.claude/skills`) and the
# resolved `agents.sharedSkills` attrset, produces a `home.file` attrset whose
# keys are `<prefix>/<name>` and whose sources are built via `mkSource`. Both
# agent target modules call this helper so the two install locations stay in
# lockstep — change the rendering once, both targets pick it up.
#
# Inputs:
#   lib       — nixpkgs lib (for `mapAttrs'`).
#   mkSource  — source helper from `modules/home/mkSource.nix`, already
#               instantiated with the caller's `config`/`self`/`editable` so
#               this helper does not need to thread those arguments.
#
# Usage:
#   let
#     renderSharedSkills = import ./renderSharedSkills.nix { inherit lib mkSource; };
#   in {
#     home.file = renderSharedSkills ".agents/skills" config.agents.sharedSkills;
#   }
{
  lib,
  mkSource,
}:
prefix: sources:
lib.mapAttrs' (name: src: {
  name = "${prefix}/${name}";
  value.source = mkSource src;
}) sources
