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
      # Tokyo Night as the Herdr TUI 0.9.5 draws it (`Palette::tokyo_night`
      # in its `src/app/state.rs`), in the app's theme format; the app
      # derives its panel colors from these.
      ".config/herdr-app/themes/tokyo-night.json".source = ./themes/tokyo-night.json;
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

      # The app writes settings.json itself (zoom, fonts, sounds, core;
      # herdr-app `src/persist.rs`), so it is an ordinary writable file rather
      # than a link. Each switch sets the keys in `./settings.json` and keeps
      # every other key the app saved; an in-app change to a declared key,
      # such as zooming `font_size`, lasts until the next switch. Theme picks
      # are not among the app's writes: they go to the unmanaged
      # `layouts/.state/`. After `linkGeneration`, which removes the link
      # older generations made at this path, so the merge never writes
      # through it into a checkout. A failure fails the switch.
      herdrAppSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] (
        lib.hm.generators.mkImpureConfigMerger {
          inherit pkgs;
          format = "json";
          empty = "{}";
          path = "${config.home.homeDirectory}/.config/herdr-app/settings.json";
          staticSettings = ./settings.json;
          jqOperation = "$dynamic * $static";
        }
      );

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
