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
  # `herdr-app commands`, which needs no window), a `<mod>.<command>` for a
  # shipped or personal mod, `send:` or `terminal`; a `mod.open:` naming
  # neither a shipped mod nor a personal one from `./mods`.
  #
  # `keys.nix` keeps keys.json sections apart from its prefix bindings (the
  # keystroke typed in prefix mode). `ctrl-b` alone opens prefix mode, so the
  # check also fails when `global` does not bind `ctrl-b` to
  # `mod.open:prefix` or `mod:prefix` does not bind it to `prefix.ctrl-b`,
  # when any other section binds `ctrl-b` alone to another action, and on a
  # chord starting with `ctrl-b`, which could never fire.
  # The `prefix` mod reads the prefix bindings from `prefixBindings`. The
  # check validates their actions the same way, and also rejects a prefix
  # binding the mod cannot run: a key that is not one keystroke, `terminal`,
  # or a `send:` whose text is not exactly one control character
  # U+0001-U+001A (the mod types it as its ctrl- key). It also rejects a
  # prefix keystroke that the merged `global`, a `layout:` section, or
  # `mod:prefix` binds alone: the app's keymap handles that keystroke before
  # the prefix popup's key listener sees it. `ctrl-b` is exempt because
  # `mod:prefix` hands it to the mod.
  keysNix = import ./keys.nix;
  prefixBindings = pkgs.writeText "herdr-app-prefix-bindings.json" (builtins.toJSON keysNix.prefix);
  keysOverrides = pkgs.writeText "herdr-app-keys-overrides.json" (builtins.toJSON keysNix.sections);
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
          --slurpfile prefix ${prefixBindings} \
          '
            def action_problem($action):
              ($action | index(":")) as $colon
              | (if $colon == null then $action else $action[:$colon] end) as $name
              | (if $colon == null then null else $action[$colon + 1:] end) as $argument
              | if $action == "terminal" or ($action | startswith("send:")) then empty
                elif $name == "mod.open" and ($argument | IN($mods[0][]) | not) then "unknown mod in \($action | tojson)"
                elif ($name | IN($commands[0][])) then empty
                elif ($name | index(".")) as $dot | $dot != null and ($name[:$dot] | IN($mods[0][])) and $name[$dot + 1:] != "" then empty
                else "unknown action \($action | tojson)"
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
                    else
                      (.key | split(" ") | map(select(. != ""))) as $strokes
                      | if $strokes == ["ctrl-b"] and $section == "mod:prefix" and .value != "prefix.ctrl-b" then "\($section).\(.key): ctrl-b in prefix mode must go to the prefix mod (prefix.ctrl-b)"
                        elif $strokes == ["ctrl-b"] and $section != "mod:prefix" and .value != "mod.open:prefix" then "\($section).\(.key): ctrl-b alone must open prefix mode (mod.open:prefix)"
                        elif ($strokes | length) > 1 and $strokes[0] == "ctrl-b" then "\($section).\(.key): a chord starting with ctrl-b can never fire, because prefix mode takes ctrl-b; add the key to the prefix bindings in keys.nix instead"
                        else empty
                        end
                    end
                end
            ),
            (
              if .global["ctrl-b"] == "mod.open:prefix" then empty
              else "global: ctrl-b is not bound to mod.open:prefix"
              end
            ),
            (
              if ."mod:prefix"["ctrl-b"] == "prefix.ctrl-b" then empty
              else "mod:prefix: ctrl-b is not bound to prefix.ctrl-b"
              end
            ),
            (
              to_entries[]
              | select(.key == "global" or (.key | startswith("layout:")) or .key == "mod:prefix")
              | .key as $section
              | select((.value | type) == "object")
              | .value | keys[]
              | select(test("\\s") | not) as $stroke
              | select($stroke != "ctrl-b" and ($prefix[0] | has($stroke)))
              | "prefix.\($stroke): \($section) also binds \($stroke), and that app binding takes the key before prefix mode sees it"
            ),
            (
              $prefix[0] | to_entries[]
              | "prefix.\(.key): \(
                  if (.key | test("^\\S+$") | not) then "not a single keystroke"
                  elif (.value | type) != "string" then "action is not a string"
                  elif .value == "terminal" then "terminal is not a prefix action"
                  elif (.value | startswith("send:")) then
                    (.value[5:] | explode) as $text
                    | if ($text | length) == 1 and $text[0] >= 1 and $text[0] <= 26 then empty
                      else "send: text must be one control character U+0001-U+001A"
                      end
                  else action_problem(.value)
                  end
                )"
            )
          ' keys.json > problems.txt
        if [ -s problems.txt ]; then
          echo "herdr-app key bindings (keys.nix) are invalid:" >&2
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
  # Remove jj workspaces with `ctrl-b ctrl-q` (`jj-workspace-remove`), not
  # the app's Remove worktree menu item: it runs `git worktree remove` and
  # leaves jj's record of the workspace, which `jj workspace forget <name>`
  # clears.
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
  # `changes`. `desk` also differs from `main` by drawing its status bar
  # with `prefix-status` instead of the shipped `workspace-status`, its
  # sidebar header and footer with `desk-chrome` instead of the shipped
  # `workspace-chrome`, and its list of spaces with `desk-spaces` instead
  # of the shipped `spaces`.
  #
  # A personal mod can be a clone: a copy of an upstream folder in the app's
  # source, recorded in its `mod.json` `cloned_from`, that is kept editable
  # here. Each clone is pinned in `clonedMods`, and the tree fails to build
  # when the pinned app's upstream folder no longer matches the clone's pin,
  # by a file's sha256 or by its exact file list (so an added file fails
  # too). The error names the clone, its upstream and the app version, and
  # says how to re-sync: re-clone or re-copy it, re-apply its edits, and
  # update `cloned_from.version`, the hashes and the file list. An app update
  # that leaves the upstream alone passes unchanged.
  #
  # `mods/prefix-status` is a clone of the shipped `workspace-status` mod,
  # plus a "PREFIX" pill and key hints while prefix mode is on. Its palette
  # chip and key hint open the personal `palette` mod, not `app.palette`.
  #
  # `mods/goto` is a clone of the shipped `picker` mod (the "Go to…" menu of
  # spaces and tabs), plus ctrl-j/ctrl-k to move the selection. `keys.nix`
  # opens it from `cmd-p` and prefix `w`/`g`, and the personal `palette`
  # mod's "Go to" entry and the `desk-chrome` search button open it too;
  # anything else that opens the built-in `picker` by name (other layouts,
  # the built-in palette's "Go to" entry) still shows the original.
  #
  # `mods/palette` is a copy of the app's own command palette
  # (`defaults/frame/palette`, the `frame-palette` mod), which `mod.clone`
  # cannot clone: its asset path points at its own folder, and its `mod.json`
  # adds the popup overlay spec that `app.palette` opens the original with.
  # It adds ctrl-j/ctrl-k and wrap-around to the selection, and its "Go to"
  # entry opens `goto`. `keys.nix` opens it from `cmd-shift-p`, and the
  # `prefix-status` chip opens it; `app.palette` and the app menu still show
  # the original.
  #
  # `mods/desk-chrome` is a clone of the shipped `workspace-chrome` mod (the
  # sidebar header and footer), with its asset paths pointing at its own
  # folder and its search button opening `goto`. `layouts/desk.json` uses it
  # for both its sidebar header and footer; other layouts still use the
  # original `workspace-chrome`, and `app.palette` and the app menu still
  # show the original palette and picker.
  #
  # `mods/desk-spaces` is a clone of the shipped `spaces` mod (the
  # sidebar's list of spaces). In a jj checkout, where Git's HEAD is always
  # detached, a space shows what the `jj-starship-prompt` terminal prompt
  # shows: the nearest bookmark (main included), the distance from it, a
  # conflict and edits in `@`, read with
  # `--ignore-working-copy` so a look never writes a jj operation; jj
  # workspaces list under their repo's main checkout. `layouts/desk.json`
  # uses it; other layouts still use the original `spaces`.
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
  #
  # The tree adds `mods/prefix/bindings.json`, the `prefix` mod's bindings
  # generated from `keys.nix` (`prefixBindings`), so it deploys with the mod.
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

        if [[ -e ${./mods}/prefix/bindings.json ]]; then
          echo "modules/home/terminal/herdr-app/mods/prefix/bindings.json is generated from keys.nix; do not commit one" >&2
          exit 1
        fi
        cp ${prefixBindings} $out/mods/prefix/bindings.json

        ${clonedModsUpstreamCheck}

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

  # The pin of each clone in `./mods`, keyed by the clone's folder name:
  # - `upstream`: the folder it was copied from, relative to the app source.
  # - `files`: every file that folder holds, mapped to its sha256 as the app
  #   version in the clone's `cloned_from` ships it. The names are the
  #   folder's exact file list.
  # - `resync`: how to rebuild the clone from a changed upstream, before
  #   updating `cloned_from.version`, the hashes and the file list.
  clonedMods = {
    prefix-status = {
      upstream = "defaults/mods/workspace-status";
      files = {
        "main.js" = "bdc4e1b468650c1b3bc1ee081fc78bab31cefbaf96933a9200faaec58b3c0f59";
        "mod.json" = "e8e0a91d23a0addf19f9f4dab48f597f252a1d44e5063e4d6ae884a88cbf735d";
      };
      resync = "re-clone it (herdr-app do mod.clone --name workspace-status --as prefix-status) and re-apply the prefix-mode change";
    };
    goto = {
      upstream = "defaults/mods/picker";
      files = {
        "main.js" = "dfeb29ce9f3c5fc2fb0098b7baac0c09fed5348f4297c846511bc647f5f564bb";
        "mod.json" = "ca186ee1f13241f1f9b8facf092138214ca840a6a4d2865618a21934ffcda34d";
      };
      resync = "re-clone it (herdr-app do mod.clone --name picker --as goto) and re-apply its edits";
    };
    palette = {
      upstream = "defaults/frame/palette";
      files = {
        "command.svg" = "d734fb3562cd3a137ac4428b03b6fb246f407950b53b7f362a4cf64ffb745a38";
        "main.js" = "9b03ae0c36bec7168ecd58f555f9ee8b989e52f427eed5dfd4cf7af4ae34b734";
        "mod.json" = "2574a840452fa1c3c4fd946e5ac62b44ddadc52af8908aa7affcc402022a8fd4";
      };
      resync = "re-copy it (mod.clone cannot clone frame mods), rewrite its frame/palette/ asset path to mods/palette/, re-add the overlay spec app.palette opens it with to mod.json, and re-apply its edits";
    };
    desk-chrome = {
      upstream = "defaults/mods/workspace-chrome";
      files = {
        "archive.svg" = "bcb4f7103eef0133d0fae701ed5b74c8a531e20f4d38d4f37a1a83af6b582540";
        "branch.svg" = "45c696f0f646e9471e9c77aa9e237c17c784cb3d8aaecf47bf5c6e05e7e67fcd";
        "check.svg" = "bb1d520e122285018a0b9d257b7f73d78156337a09706da2b5619a75c45aa231";
        "chevron-down.svg" = "be2f2e86753c4c6bc19b1cc196611b18597cc7a553580ed2bdf80f26a5e2440d";
        "chevron-left.svg" = "1a3db31d090bce6c795dbcbd1a95cb6bb074d0b2fcd8d26e5610211e10c8291f";
        "chevron-right.svg" = "280d2c796344a22fb6cb7086edc90868a27c7812405cffb9be66a3c5835aa898";
        "circle-check.svg" = "7d9e10a404a556a239ee33ad8a5b1e415ce39d505991760115d3a515cf387426";
        "clock.svg" = "0f3d2e2b3668e96889f182ef6ab2fb66aa54d48472e83be98bd239d81f64a9cc";
        "file-text.svg" = "b00717747452168438e35e9ec6828e779bcace9497e3f6dc63f7a618a80cf4f4";
        "files.svg" = "d0cb1467cd6c7b726d19d13f7aabeebaf094991605bd9fd4a47a6d084a575d24";
        "folder-plus.svg" = "b89f6eb87b75714f01b723971ba96ee6d6969d6a7cdb878989cd9981268d92eb";
        "folder.svg" = "9d7567649afffe0523114fcff3ac9da0504ac24cabc35e0b1dc0a4d90a34beb8";
        "git-branch.svg" = "d2f7cf0c6d1944b9453268f1155da2e93374fad83beeae5ab9a7d5e3584e2204";
        "git-compare.svg" = "2bc47e7dc3c5df4cfaf82de1fdc5bf9f1bbc7f790170d5d434ed7c4ffc86295f";
        "layers.svg" = "d63f7cec8a79eec4a60755af9f2549584a61c8e349ef9f7e9a6c4af2aeb73d9d";
        "main.js" = "d32d05ae66b44890cb0625015b240fbba4cfe9b336c39fbadfb737aec64ae76c";
        "minus.svg" = "709a2f4c02741159ea14691d4fb1cbcf68073b27ec4e738bc9a73d660f409d7c";
        "mod.json" = "e8e0a91d23a0addf19f9f4dab48f597f252a1d44e5063e4d6ae884a88cbf735d";
        "monitor.svg" = "cbb2f05267714ca1ffa6411cf102bbba7da13743654e4fe518429b181cf19099";
        "panel-left.svg" = "2e67d422da7253a4efcfbc02e74c17104844d7fdb19d63210e18b2c03bfa0ab4";
        "panel-right.svg" = "85a85f016e5be2c50a3906161d190df94e3770d22e9069abf21649c9b7f36b1a";
        "pin-off.svg" = "265298d18044617313022b40f1e24bb4989fe1f18f33585786fc947bb1ab270a";
        "pin.svg" = "d4b9b5f5ef7f89e819316110ba8d8aa1d1998a30b03b4eeaf3323682890778dc";
        "plus.svg" = "109da7afa021037ac0278aa9f5e72fd53e2fa2ea1f8ea32fbf78e7d98e6301e6";
        "search.svg" = "7be6e7a558041594b46f0c22ccf0fd8d1f02458933b8038523323c874c7ad50b";
        "server.svg" = "41a942cb9c9011def4c0b9a05f4cd02f3fcc762e7617c09610bc23264786c3f7";
        "settings.svg" = "2f8dba8fb2a34431d93f83409b1058e95bf8cf3a54906f90d534a2d1a814b6e2";
        "sidebar.svg" = "2f5ce4d2f78c3740d874db721092360cd58b809dca2564ea3fb65480ed4a9471";
        "spinner.svg" = "00130fbac061db08cc967fdf2ae1378211a591c57cfb8f9b4018ec823fefea2d";
        "square-pen.svg" = "e46ff55127ad0510e9637cba346fcb5c672cf6e14e74815652358cece8a2889e";
        "square.svg" = "e475514f8a336eaa799db562ec89a87eacc5e9202c1b1f0e0ab387b6334b0d1b";
        "terminal.svg" = "a6f93e62a6ec412e6a214849be5b566cd21cff81d5570891c2e04e96c4dd964e";
        "x.svg" = "c1e53fc9bbe1a0a0b8183bcacf5ab7dbf160fd1f082594de3dcbba1cd5a71614";
      };
      resync = "re-clone it (herdr-app do mod.clone --name workspace-chrome --as desk-chrome) and re-apply its edits";
    };
    desk-spaces = {
      upstream = "defaults/mods/spaces";
      files = {
        "main.js" = "65f0f8bb48b8e9266266dc0adbd785c6d7372429db5ca9807cea2dfe0b48fefb";
        "mod.json" = "8357ce89d375376872b6db414b9555b26936b2e9d61e44275dc2e2bfe2a5783e";
      };
      resync = "re-clone it (herdr-app do mod.clone --name spaces --as desk-spaces) and re-apply its edits";
    };
  };

  # Bash that exits 1 when any clone's upstream folder in the pinned app
  # differs from its `clonedMods` pin, by a file's hash or by the file list.
  clonedModsUpstreamCheck = lib.concatStrings (
    lib.mapAttrsToList (
      name: clone:
      let
        upstream = "${herdrApp.src}/${clone.upstream}";
        hashes = pkgs.writeText "herdr-app-${name}-upstream.sha256" (
          lib.concatStrings (lib.mapAttrsToList (file: hash: "${hash}  ${file}\n") clone.files)
        );
        fileList = pkgs.writeText "herdr-app-${name}-upstream-files.txt" (
          lib.concatLines (lib.attrNames clone.files)
        );
        message = "herdr-app ${herdrApp.version} no longer ships ${clone.upstream} as modules/home/terminal/herdr-app/mods/${name} was cloned from it (see the hash or file-list mismatch above); ${clone.resync}, then update cloned_from.version in its mod.json and the hashes and file list in clonedMods.${name}";
      in
      # bash
      ''
        if ! (cd ${upstream} && sha256sum --check --quiet ${hashes}) \
          || ! diff <(LC_ALL=C sort ${fileList}) <(find ${upstream} -mindepth 1 -printf '%P\n' | LC_ALL=C sort) >&2; then
          echo ${lib.escapeShellArg message} >&2
          exit 1
        fi
      ''
    ) clonedMods
  );

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

  # The folder picker the `space-new` mod runs in a popup terminal. It takes
  # its tools as arguments so the fixtures can pass fakes; `spaceNew` passes
  # the real ones.
  spaceNewPicker = pkgs.writeShellApplication {
    name = "herdr-space-new-picker";
    text = builtins.readFile ./space-new.sh;
  };

  # The `space-new` mod runs the picker through this path, so failing
  # fixtures fail the build.
  checkedSpaceNewPicker = pkgs.runCommandLocal "herdr-space-new-picker-checked" { } ''
    bash ${./space-new-test.sh} ${spaceNewPicker}/bin/herdr-space-new-picker ${pkgs.fd}/bin/fd
    ln -s ${spaceNewPicker} "$out"
  '';

  spaceNew = pkgs.writeShellScript "herdr-space-new" ''
    exec ${checkedSpaceNewPicker}/bin/herdr-space-new-picker ${pkgs.fd}/bin/fd ${pkgs.fzf}/bin/fzf ${herdrApp}/bin/herdr-app
  '';

  # The launcher mods (`find`, `jj-workspace-new`, `jj-workspace-pick`,
  # `jj-workspace-remove`, `space-new`) start their CLIs by the absolute store
  # paths this file maps CLI names to. A bare name would resolve on the core's
  # PATH, which depends on whoever started the core. Read-only, because it
  # holds store paths.
  dotfilesPaths = (pkgs.formats.json { }).generate "herdr-app-dotfiles-paths.json" {
    herdr-find = "${dotfilesPackages.herdr-find.cli}/bin/herdr-find";
    herdr-jj-workspace = "${dotfilesPackages.herdr-jj-workspaces.cli}/bin/herdr-jj-workspace";
    herdr-space-new = "${spaceNew}";
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
