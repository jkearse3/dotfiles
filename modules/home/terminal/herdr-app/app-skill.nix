# The `herdr-app` agent skill: the app's `herdr-app --skill` text as a
# `SKILL.md` with frontmatter.
{
  herdrApp,
  lib,
  pkgs,
}:
let
  # The app ships its agent skill only as `herdr-app --skill` output, which
  # prints without opening a window. That text has no frontmatter, and pi
  # skips skills without a description (pi `docs/skills.md`), so the build
  # adds one. It fails if a later app version starts shipping its own
  # frontmatter, so this one gets dropped instead of doubled.
  appSkillDescription = "Drive the Herdr desktop app's window with herdr-app: inspect it, show or arrange spaces, tabs, panes and layouts, and customize its layouts, keys and mods. Use when the user mentions the Herdr app or asks to change what its window shows. For starting, reading or coordinating terminals and agents, use herdr-core (hc) instead.";
in
pkgs.runCommand "herdr-app-skill" { } ''
  mkdir -p $out
  ${herdrApp}/bin/herdr-app --skill > body.md
  test -s body.md
  if [ "$(head -n 1 body.md)" = "---" ]; then
    echo "herdr-app --skill now has frontmatter; drop the generated one." >&2
    exit 1
  fi
  {
    printf '%s\n' '---' 'name: herdr-app' ${lib.escapeShellArg "description: ${builtins.toJSON appSkillDescription}"} '---' ""
    cat body.md
  } > $out/SKILL.md
''
