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

  # The package ships only `bin/herdr-app`, which Spotlight and the Dock
  # cannot launch. This bundle follows upstream `scripts/install-macos`. Its
  # executable is the real app binary, not the package's PATH wrapper, so the
  # process belongs to the bundle and shows its name and icon in the Dock.
  # Running from `Herdr.app/Contents/MacOS/Herdr`, the app links
  # `~/.local/bin/herdr-app` to itself (herdr-app `src/core_bin/cli_link.rs`);
  # the profile's `herdr-app` stays ahead of it on PATH.
  herdrApp = dotfilesPackages.herdr-app;
  herdrAppInfoPlist = pkgs.writeText "Info.plist" (
    lib.generators.toPlist { escape = true; } {
      CFBundleExecutable = "Herdr";
      CFBundleIdentifier = "dev.herdr.app";
      CFBundleName = "Herdr";
      CFBundleDisplayName = "Herdr";
      CFBundleIconFile = "Herdr";
      CFBundlePackageType = "APPL";
      CFBundleShortVersionString = herdrApp.version;
      CFBundleVersion = herdrApp.version;
      NSPrincipalClass = "NSApplication";
      NSHighResolutionCapable = true;
      # Finder and Dock launches do not get the login shell's PATH. The app
      # looks for `hc` on PATH, and the profile's comes first so that it
      # finds the wrapped one, which drops the TUI's pane variables. On those
      # launches the app also puts the login shell's PATH in front
      # (herdr-app `src/core_bin.rs` `fill_path`).
      LSEnvironment.PATH = lib.concatStringsSep ":" [
        "${config.home.profileDirectory}/bin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ];
    }
  );
  herdrAppBundle = pkgs.runCommandLocal "herdr-app-bundle" { } ''
    contents=$out/Applications/Herdr.app/Contents
    mkdir -p $contents/MacOS $contents/Resources
    cp ${herdrAppInfoPlist} $contents/Info.plist
    cp ${herdrApp}/bin/.herdr-app-wrapped $contents/MacOS/Herdr
    cp ${herdrApp.src}/assets/icons/Herdr.icns $contents/Resources/Herdr.icns
  '';

  installBundle = pkgs.writeShellApplication {
    name = "herdr-app-install-bundle";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./install-bundle.sh;
  };

  # The activation runs the script through this path, so failing fixtures
  # fail the build.
  checkedInstallBundle = pkgs.runCommandLocal "herdr-app-install-bundle-checked" { } ''
    bash ${./install-bundle-test.sh} ${installBundle}/bin/herdr-app-install-bundle
    ln -s ${installBundle} "$out"
  '';
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
    };

    activation = {
      # `targets.darwin.copyApps` stays off (applications are managed outside
      # Home Manager), so this step installs only `~/Applications/Herdr.app`
      # and leaves every other entry there alone. A failure fails the switch.
      herdrAppBundle = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run ${checkedInstallBundle}/bin/herdr-app-install-bundle ${herdrAppBundle}/Applications/Herdr.app ${lib.escapeShellArg "${config.home.homeDirectory}/Applications/Herdr.app"}
      '';
    };
  };
  agents.extraSkills = {
    herdr-app = appSkill;
    herdr-core = "${dotfilesPackages.herdr-core}/share/skills/herdr-core/herdr-core";
  };
}
