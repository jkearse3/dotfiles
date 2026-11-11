# The tree of personal mods and layouts each switch copies into
# `~/.config/herdr-app` (`deployTree`), the shipped entries the copy never
# removes (`shippedEntries`), and the fixture-checked script that copies it
# (`checkedDeploy`).
{
  herdrApp,
  herdrAppModsChecked,
  lib,
  modNames,
  personalMods,
  pkgs,
  prefixBindings,
}:
let
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
  # `desk.json` started as a copy of the shipped `main` layout without the
  # Git Changes panel, whose commit box would make Git commits behind jj's
  # back. Showing it is a one-time step with the window open,
  # `herdr-app do layout.switch --name desk` (or the palette); the app
  # remembers the shown layout. The escape hatch
  # (`ctrl-alt-shift-escape`) renames it aside and returns to `main`; the
  # next switch puts the file back, and showing it again is the same step.
  # The app's structural rewrites (a mod docking) last until the next
  # switch; panel sizes live in `layouts/.state/` and stay. The shipped
  # Changes button would fail here, with no `changes` node; it stays off
  # while `workspace.panels` (set by the welcome screen) leaves out
  # `changes`. `desk` also differs from `main` by drawing its status bar
  # with `prefix-status` instead of the shipped `workspace-status`, its
  # sidebar header and footer with `desk-chrome` instead of the shipped
  # `workspace-chrome`, and its sidebar with one list, `desk-spaces`, each
  # space with its agents under it, instead of the shipped `spaces` over
  # the shipped `agents`.
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
  # The tree adds `mods/prefix/bindings.json`, the `prefix` mod's bindings and
  # hints generated from `keys.nix` (`prefixBindings`), so it deploys with the
  # mod.
  #
  # Mods share source through `./mod-lib`: a mod that uses a shared file
  # holds a relative link to it, `./mods/<mod>/<file>` ->
  # `../../mod-lib/<file>`, and imports it as `./<file>`. The app refuses
  # imports that leave a mod's own folder (gpui-kit `engine/quickjs/mod.rs`,
  # `AppModules`'s `Resolver::resolve`), and a deployed link would point out
  # of the folder, so the tree copies each mod with its links resolved. The
  # tree depends on `herdrAppModsChecked` (`packages/herdr-app-mods-checked`),
  # which fails when a link breaks the rules there or a mod fails
  # `herdr-app check`, so a mod that would not load fails the build.
  #
  # `modSources` holds `./mods` beside `./mod-lib`, so the mods' links
  # resolve when the tree copies them.
  modSources = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./mods
      ./mod-lib
    ];
  };

  deployTree =
    pkgs.runCommandLocal "herdr-app-deploy-tree" { nativeBuildInputs = [ pkgs.jq ]; } # bash
      ''
        test -e ${herdrAppModsChecked}

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
          cp -RL ${modSources}/mods/"$name" $out/mods/"$name"
          chmod -R u+w $out/mods/"$name"
          rm -f $out/mods/"$name"/gpui-kit.d.ts $out/mods/"$name"/jsconfig.json
        done

        if [[ -e ${./mods}/prefix/bindings.json ]]; then
          echo "modules/home/terminal/herdr-app/mods/prefix/bindings.json is generated from keys.nix; do not commit one" >&2
          exit 1
        fi
        cp ${prefixBindings} $out/mods/prefix/bindings.json

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
in
{
  inherit deployTree shippedEntries checkedDeploy;
}
