{
  config,
  dotfilesPackages,
  lib,
  mkSource,
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

  herdrApp = dotfilesPackages.herdr-app;

  appSkill = import ./app-skill.nix { inherit herdrApp lib pkgs; };

  inherit
    (import ./bundle.nix {
      inherit herdrApp lib pkgs;
      inherit (config.home) profileDirectory;
    })
    herdrAppBundle
    checkedInstallBundle
    ;

  inherit (import ./mod-names.nix { inherit herdrApp lib pkgs; }) personalMods modNames;

  inherit (import ./keys-json.nix { inherit herdrApp modNames pkgs; }) keysJson prefixBindings;

  inherit
    (import ./deploy.nix {
      herdrAppMods = dotfilesPackages.herdr-app-mods;
      inherit
        herdrApp
        lib
        modNames
        personalMods
        pkgs
        prefixBindings
        ;
    })
    deployTree
    shippedEntries
    checkedDeploy
    ;

  spaceNew = import ./space-new.nix { inherit herdrApp pkgs; };

  dotfilesPaths = import ./dotfiles-paths.nix {
    inherit dotfilesPackages pkgs spaceNew;
    # The user's interactive jj, so the sidebar reads repositories with it.
    jujutsu = config.programs.jujutsu.package;
  };
in
{
  imports = [
    ../../agents/skills.nix
    ../../lib/source.nix
  ];

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
    file = {
      ".config/herdr-core/config.toml".source = coreConfig;
      # Editable, because the app writes settings.json itself (zoom, fonts,
      # sounds, core), following the link (herdr-app `src/persist.rs`), so
      # those writes show up as working-tree diffs here. Theme picks are not
      # among them: they go to the unmanaged `layouts/.state/`. Edits made
      # here reach a running app on its poll, about 10 s, because its file
      # watcher sees `~/.config/herdr-app`, not the link targets.
      ".config/herdr-app/settings.json".source = mkSource ./settings.json;
      # Tokyo Night as the Herdr TUI 0.9.5 draws it (`Palette::tokyo_night`
      # in its `src/app/state.rs`), in the app's theme format; the app
      # derives its panel colors from these.
      ".config/herdr-app/themes/tokyo-night.json".source = mkSource ./themes/tokyo-night.json;
      ".config/herdr-app/dotfiles-paths.json".source = dotfilesPaths;
    };

    activation = {
      # `targets.darwin.copyApps` stays off (applications are managed outside
      # Home Manager), so this step installs only `~/Applications/Herdr.app`
      # and leaves every other entry there alone. A failure fails the switch.
      herdrAppBundle = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run ${checkedInstallBundle}/bin/herdr-app-install-bundle ${herdrAppBundle}/Applications/Herdr.app ${lib.escapeShellArg "${config.home.homeDirectory}/Applications/Herdr.app"}
      '';

      # A copy, not a `home.file` link: the app reloads keys.json only when its
      # mtime changes (herdr-app `src/window.rs`), and store files all share
      # mtime 1, so a link would never reload. The escape hatch
      # (`ctrl-alt-shift-escape`) also renames keys.json aside and writes the
      # defaults, which the next switch overwrites like any other content.
      herdrAppKeys = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg "${config.home.homeDirectory}/.config/herdr-app"}
        run ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg "${config.home.homeDirectory}/.config/herdr-app/keys.json"}
        run ${pkgs.coreutils}/bin/install -m0644 ${keysJson} ${lib.escapeShellArg "${config.home.homeDirectory}/.config/herdr-app/keys.json"}
      '';

      # After `linkGeneration`, which removes the links older generations
      # made at these paths. A failure fails the switch.
      herdrAppDeploy = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run ${checkedDeploy}/bin/herdr-app-deploy ${deployTree} ${lib.escapeShellArg "${config.home.homeDirectory}/.config/herdr-app"} ${shippedEntries}
      '';
    };
  };
  agents.extraSkills = {
    herdr-app = appSkill;
    herdr-core = "${dotfilesPackages.herdr-core}/share/skills/herdr-core/herdr-core";
  };
}
