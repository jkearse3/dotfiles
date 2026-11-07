{
  config,
  dotfilesPackages,
  lib,
  pkgs,
  ...
}:
let
  # Read-only because it holds store and profile paths, and the core never
  # writes it (herdr-core `config.rs`).
  coreConfig = (pkgs.formats.toml { }).generate "herdr-core-config.toml" {
    # A core started from a restricted environment, such as Home Manager
    # activation or a Finder-launched app, would otherwise pick its shell
    # from that environment rather than the user's fish.
    shell = [ "${config.home.profileDirectory}/bin/fish" ];
    # Without this the socket lives under `XDG_RUNTIME_DIR`, which a login
    # agent exports only after apps macOS restores at login may have started
    # (`modules/home/shell/runtime-directory/default.nix`), so the app's core
    # and later shells could pick different sockets. The core creates the
    # parent directory itself, mode 0700 (herdr-core `paths.rs` `create_dirs`).
    socket = "${config.home.homeDirectory}/.local/state/herdr-core/core.sock";
  };

  # The app ships its agent skill only as `herdr-app --skill` output, which
  # prints without opening a window. That text has no frontmatter, and pi
  # skips skills without a description (pi `docs/skills.md`), so the build
  # adds one. It fails if a later app version starts shipping its own
  # frontmatter, so this one gets dropped instead of doubled.
  appSkillDescription = "Drive the Herdr desktop app's window with herdr-app: inspect it, show or arrange spaces, tabs, panes and layouts, and customize its layouts, keys and mods. Use when the user mentions the Herdr app or asks to change what its window shows. For starting, reading or coordinating terminals and agents, use herdr-core (hc) instead.";
  appSkill = pkgs.runCommand "herdr-app-skill" { } ''
    mkdir -p $out
    ${dotfilesPackages.herdr-app}/bin/herdr-app --skill > body.md
    test -s body.md
    if [ "$(head -n 1 body.md)" = "---" ]; then
      echo "herdr-app --skill now has frontmatter; drop the generated one." >&2
      exit 1
    fi
    {
      printf '%s\n' '---' 'name: herdr-app' ${lib.escapeShellArg "description: ${builtins.toJSON appSkillDescription}"} '---' ""
      cat body.md
    } > $out/SKILL.md
  '';
in
{
  imports = [ ../../agents/skills.nix ];

  home = {
    # The wrapped `hc` drops the Herdr TUI's pane variables, so a core first
    # started from a TUI pane does not pass them to app terminals.
    # A switch leaves a running core on its old version; `hc server restart`
    # moves it. Nothing restarts it automatically because a core's saved
    # state only moves forward.
    packages = [
      dotfilesPackages.herdr-app
      dotfilesPackages.herdr-core
    ];
    file.".config/herdr-core/config.toml".source = coreConfig;
  };
  agents.extraSkills = {
    herdr-app = appSkill;
    herdr-core = "${dotfilesPackages.herdr-core}/share/skills/herdr-core/herdr-core";
  };
}
