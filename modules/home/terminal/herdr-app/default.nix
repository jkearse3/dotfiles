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
  # app's shipped mods and each folder in `./mods`. The keys and layout
  # checks below reject any other name.
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

  # Personal layouts and mods are copied into `~/.config/herdr-app` on each
  # switch rather than linked with `mkSource` like other editable config:
  # - The app writes its typings (`gpui-kit.d.ts`, `jsconfig.json`) into
  #   every mod folder it loads, which would land in this working tree.
  # - The app reloads a mod or layout when a file's mtime changes, and store
  #   files all share mtime 1, so a store link would never reload.
  # - A live link put each edit in front of the running window mid-edit, and
  #   a layout could go live before the mods it names were linked, which
  #   replaced the window's layout with `main`.
  # A copy changes only at a switch, after the build has checked the layouts
  # against the mods. Home Manager refuses to link over these copies, so
  # activating an older generation that linked them fails with "Existing
  # file ... would be clobbered"; first remove each entry the deploy's
  # manifest `dotfiles-owned.txt` lists, then the manifest itself.
  #
  # `desk.json` is a clone of the shipped `main` layout at its `cloned_from`
  # version, without the Git Changes panel, whose commit box would make Git
  # commits behind jj's back. On an app update, compare that version's
  # `defaults/layouts/main.json` with the new one, and if it changed,
  # re-clone it without that panel. Showing it is a one-time step with the
  # window open, `herdr-app do layout.switch --name desk` (or the
  # palette); the app remembers the shown layout. The escape hatch
  # (`ctrl-alt-shift-escape`) renames it aside and returns to `main`; the
  # next switch puts the file back, and showing it again is the same step.
  # The app's structural rewrites (a mod docking) last until the next
  # switch; panel sizes live in `layouts/.state/` and stay. The shipped
  # Changes button would fail here, with no `changes` node; it stays off
  # while `workspace.panels` (set by the welcome screen) leaves out
  # `changes`.
  #
  # The tree fails to build when a personal mod or layout is named like a
  # shipped one, which the app would overwrite on its next start, or starts
  # with a dot, which the app ignores, or when `./layouts` holds anything but
  # regular files. It also fails when a layout names a mod neither shipped
  # nor in `./mods`. A layout names a mod with any string `mod` key at any
  # depth, which the running window would answer by hiding that layout and
  # showing `main`, and with its root `terminal_menu`, which the app would
  # quietly replace with the shipped `menu`, warning only in its log.
  # `frame-` names are exempt (herdr-app `src/window.rs` `missing_mods` and
  # `open_menu`, `src/layout.rs`). The app loads only `*.json` layouts, so
  # only they are checked.
  deployTree =
    pkgs.runCommandLocal "herdr-app-deploy-tree" { nativeBuildInputs = [ pkgs.jq ]; } # bash
      ''
        mkdir -p $out/mods $out/layouts

        for name in ${lib.escapeShellArgs personalMods}; do
          if [[ $name == .* ]]; then
            echo "herdr-app mod folder $name in modules/home/terminal/herdr-app/mods starts with a dot, which the app ignores" >&2
            exit 1
          fi
          if [[ -e ${herdrApp.src}/defaults/mods/$name ]]; then
            echo "herdr-app mod folder $name in modules/home/terminal/herdr-app/mods is named like a mod shipped with herdr-app ${herdrApp.version}; rename it" >&2
            exit 1
          fi
          cp -R ${./mods}/"$name" $out/mods/"$name"
          chmod -R u+w $out/mods/"$name"
          rm -f $out/mods/"$name"/gpui-kit.d.ts $out/mods/"$name"/jsconfig.json
        done

        shopt -s dotglob nullglob
        failed=
        for path in ${./layouts}/*; do
          name=''${path##*/}
          if [[ $name == .* ]]; then
            echo "herdr-app layout $name in modules/home/terminal/herdr-app/layouts starts with a dot, which the app ignores" >&2
            exit 1
          fi
          if [[ -L $path || ! -f $path ]]; then
            echo "herdr-app layout $name in modules/home/terminal/herdr-app/layouts is not a regular file" >&2
            exit 1
          fi
          if [[ -e ${herdrApp.src}/defaults/layouts/$name ]]; then
            echo "herdr-app layout $name in modules/home/terminal/herdr-app/layouts is named like a layout shipped with herdr-app ${herdrApp.version}; rename it" >&2
            exit 1
          fi
          if [[ $name == *.json ]]; then
            if ! problems=$(jq -r --arg layout "$name" --slurpfile mods ${modNames} '
                [(.. | objects | .mod? | strings), (.terminal_menu? | strings)]
                | unique[]
                | select(startswith("frame-") | not)
                | select(IN($mods[0][]) | not)
                | "herdr-app layout \($layout) in modules/home/terminal/herdr-app/layouts names mod \(tojson), which is neither shipped with herdr-app ${herdrApp.version} nor a folder in modules/home/terminal/herdr-app/mods"
              ' "$path" 2>/dev/null); then
              problems="herdr-app layout $name in modules/home/terminal/herdr-app/layouts is not valid JSON"
            fi
            if [[ -n $problems ]]; then
              printf '%s\n' "$problems" >&2
              failed=1
            fi
          fi
          cp "$path" $out/layouts/"$name"
        done
        if [[ -n $failed ]]; then
          exit 1
        fi
      '';

  # The app's shipped mods and layouts, which `deploy.sh` never removes, even
  # when an older switch deployed a personal entry by that name.
  shippedEntries = pkgs.runCommandLocal "herdr-app-shipped-entries.txt" { } ''
    cd ${herdrApp.src}/defaults
    for path in mods/* layouts/*; do
      printf '%s\n' "$path"
    done > $out
  '';

  deploy = pkgs.writeShellApplication {
    name = "herdr-app-deploy";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
    ];
    text = builtins.readFile ./deploy.sh;
  };

  # The activation runs the script through this path, so failing fixtures
  # fail the build.
  checkedDeploy = pkgs.runCommandLocal "herdr-app-deploy-checked" { } ''
    bash ${./deploy-test.sh} ${deploy}/bin/herdr-app-deploy
    ln -s ${deploy} "$out"
  '';

  # The `find` launcher mod starts its CLI by the absolute store path this
  # file maps CLI names to. A bare name would resolve on the core's PATH,
  # which depends on whoever started the core. Read-only, because it holds
  # store paths.
  dotfilesPaths = (pkgs.formats.json { }).generate "herdr-app-dotfiles-paths.json" {
    herdr-find = "${dotfilesPackages.herdr-find.cli}/bin/herdr-find";
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
