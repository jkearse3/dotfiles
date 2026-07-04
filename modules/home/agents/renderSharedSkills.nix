# Render the shared-skills registry into a single parent directory.
#
# Given a `home.file` prefix (e.g. `.agents/skills` or `.claude/skills`) and the
# resolved `agents.sharedSkills` attrset, produces a `home.file` attrset whose
# keys are `<prefix>/<name>` and whose sources point directly at the registered
# paths. Both agent target modules call this helper so the two install locations
# stay in lockstep — change the rendering once, both targets pick it up.
#
# Inputs:
#   lib — nixpkgs lib (for `mapAttrs'`).
#
# Usage:
#   let
#     renderSharedSkills = import ./renderSharedSkills.nix { inherit lib; };
#   in {
#     home.file = renderSharedSkills ".agents/skills" config.agents.sharedSkills;
#   }
{ lib }:
prefix: sources:
lib.mapAttrs' (name: src: {
  name = "${prefix}/${name}";
  value.source = src;
}) sources
