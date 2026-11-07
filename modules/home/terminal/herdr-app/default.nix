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

  # Every mod name the app will find installed, as a JSON array: the pinned
  # app's shipped mods and each folder in `./mods`. The keys check below
  # rejects any other name.
  personalMods = lib.optionals (builtins.pathExists ./mods) (
    lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./mods))
  );
  modNames =
    pkgs.runCommandLocal "herdr-app-mod-names.json" { nativeBuildInputs = [ pkgs.jq ]; } # bash
      ''
        find ${herdrApp.src}/defaults/mods -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
          | jq -Rn --argjson personal ${lib.escapeShellArg (builtins.toJSON personalMods)} '[inputs] + $personal' > $out
      '';

  # The app never merges a user's keys.json with its defaults: it writes the
  # defaults only when the file is missing (herdr-app `src/keys.rs` `load`).
  # So the build merges the pinned app's defaults with `keys.nix` per
  # section, and a new upstream default arrives with the next app update.
  # The build fails on an override the app would reject or silently drop at
  # runtime: an action that is not one of the app's commands (listed by
  # `herdr-app commands`, which needs no window), `send:` or `terminal`; a
  # `mod.open:` naming neither a shipped mod nor a personal one from `./mods`;
  # or a binding of `ctrl-b` alone, which would swallow the chord prefix.
  keysOverrides = pkgs.writeText "herdr-app-keys-overrides.json" (
    builtins.toJSON (import ./keys.nix)
  );
  keysJson =
    pkgs.runCommandLocal "herdr-app-keys.json" { nativeBuildInputs = [ pkgs.jq ]; } # bash
      ''
        ${herdrApp}/bin/herdr-app commands > commands.json
        jq '[.[].name]' commands.json > command-names.json
        jq -s '.[0] * .[1]' ${herdrApp.src}/defaults/keys.macos.json ${keysOverrides} > keys.json

        jq -r \
          --slurpfile commands command-names.json \
          --slurpfile mods ${modNames} \
          --slurpfile overrides ${keysOverrides} \
          '
            def action_problem($action):
              ($action | index(":")) as $colon
              | (if $colon == null then $action else $action[:$colon] end) as $name
              | (if $colon == null then null else $action[$colon + 1:] end) as $argument
              | if $action == "terminal" or ($action | startswith("send:")) then empty
                elif ($name | IN($commands[0][]) | not) then "unknown action \($action | tojson)"
                elif $name == "mod.open" and ($argument | IN($mods[0][]) | not) then "unknown mod in \($action | tojson)"
                else empty
                end;

            (
              $overrides[0] | to_entries[] | .key as $section
              | .value | to_entries[]
              | "\($section).\(.key): \(action_problem(.value))"
            ),
            (
              to_entries[] | .key as $section
              | if (.value | type) != "object" then "\($section): not an object of bindings"
                else .value | to_entries[]
                  | if (.value | type) != "string" then "\($section).\(.key): action is not a string"
                    elif (.key | split(" ") | map(select(. != ""))) == ["ctrl-b"] then "\($section).\(.key): binds the ctrl-b chord prefix alone"
                    else empty
                    end
                end
            )
          ' keys.json > problems.txt
        if [ -s problems.txt ]; then
          echo "herdr-app keys.json overrides (keys.nix) are invalid:" >&2
          cat problems.txt >&2
          exit 1
        fi
        cp keys.json $out
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
    };
  };
  agents.extraSkills = {
    herdr-app = appSkill;
    herdr-core = "${dotfilesPackages.herdr-core}/share/skills/herdr-core/herdr-core";
  };
}
