# TypeScript declarations for authoring herdr-app mods, written by the pinned
# herdr-app itself.
#
# `herdr-app types <folder>` is gpui-shell's typings command with Herdr's
# `herdr` module installed (herdr-app `src/main.rs`). It writes the same two
# files the running app writes into every mod folder it loads:
# - `gpui-kit.d.ts`: the `gpui-kit` family, the Node-like modules, the
#   `herdr` module, and the window globals.
# - `jsconfig.json`: the compiler options the app expects a mod to be checked
#   with, each explained in its `// why` entry.
# Running the binary that home-manager installs means the declarations cannot
# describe another version than the app that loads the mods.
{
  herdr-app,
  pkgs,
}:
pkgs.runCommandLocal "herdr-app-mod-types-${herdr-app.version}"
  {
    passthru.herdrAppVersion = herdr-app.version;
    meta.description = "Type declarations for herdr-app mods, written by herdr-app";
  }
  ''
    export HOME="$TMPDIR"
    mkdir -p $out
    ${herdr-app}/bin/herdr-app types $out

    # A layout change upstream would otherwise surface as editors silently
    # losing every type; fail here, naming what is missing.
    for file in gpui-kit.d.ts jsconfig.json; do
      if [[ ! -s $out/$file ]]; then
        echo "herdr-app-mod-types: herdr-app ${herdr-app.version} types wrote no $file" >&2
        exit 1
      fi
    done
    if ! grep -Fqx 'declare module "herdr" {' $out/gpui-kit.d.ts; then
      echo "herdr-app-mod-types: herdr-app ${herdr-app.version} types left out the herdr module" >&2
      exit 1
    fi
  ''
