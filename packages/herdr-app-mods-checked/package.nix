# Gate for the personal herdr-app mods: this builds only when every mod in
# `modules/home/terminal/herdr-app/mods` loads in the pinned app and the mods'
# links to their shared code in `mod-lib` follow the rules below.
#
# A mod imports shared code as `./<file>`, because the app refuses imports
# that leave a mod's own folder (gpui-kit `engine/quickjs/mod.rs`,
# `AppModules`'s `Resolver::resolve`). Each such file in a mod folder is a
# relative link to `../../mod-lib/<file>`; the deploy tree copies the target in
# place of the link. The link rules keep that layout: a mod file named like a
# `mod-lib` file is exactly that link, a mod folder holds no other link, no
# link dangles, and every `mod-lib` file reaches at least one mod.
#
# `herdr-app check` then loads each mod from a copy with its links resolved,
# as the deploy tree holds it, so a missing shared file or an import of a name
# the app does not export fails here.
#
# This is a package rather than only part of the home build because
# `nix flake check` builds no home configuration. The herdr-app home module's
# deploy tree references this output, so a failing mod also fails the switch.
{
  herdr-app,
  modSources,
  pkgs,
}:
pkgs.runCommandLocal "herdr-app-mods-checked" { } ''
  shopt -s dotglob nullglob

  # `modSources` holds `mods` and `mod-lib` as they sit in
  # `modules/home/terminal/herdr-app`, so a link's relative target resolves
  # the same way here as in the checkout.
  linkFailed=
  for modPath in ${modSources}/mods/*/*; do
    path=modules/home/terminal/herdr-app/mods/''${modPath#${modSources}/mods/}
    name=''${modPath##*/}
    if [[ -e ${modSources}/mod-lib/$name || -L ${modSources}/mod-lib/$name ]]; then
      if [[ ! -L $modPath ]]; then
        echo "$path is named like mod-lib/$name but is not a link; replace it with a link to ../../mod-lib/$name" >&2
        linkFailed=1
      elif [[ $(readlink "$modPath") != "../../mod-lib/$name" ]]; then
        echo "$path links to $(readlink "$modPath"), not ../../mod-lib/$name" >&2
        linkFailed=1
      fi
    elif [[ -L $modPath ]]; then
      echo "$path is a link, but a mod folder may only link files of mod-lib, as ../../mod-lib/<same name>" >&2
      linkFailed=1
    fi
    if [[ -L $modPath && ! -e $modPath ]]; then
      echo "$path is a dangling link to $(readlink "$modPath")" >&2
      linkFailed=1
    fi
  done
  for libPath in ${modSources}/mod-lib/*; do
    name=''${libPath##*/}
    linked=
    for modPath in ${modSources}/mods/*/"$name"; do
      if [[ -L $modPath ]]; then
        linked=1
      fi
    done
    if [[ -z $linked ]]; then
      echo "modules/home/terminal/herdr-app/mod-lib/$name is linked by no mod; link it into a mod folder as ./$name or delete it" >&2
      linkFailed=1
    fi
  done
  if [[ -n $linkFailed ]]; then
    exit 1
  fi

  # `check` writes typings into the mod folder and state under `$HOME`, so it
  # runs on a writable copy with the links resolved, as the deploy tree holds
  # the mod, and with HOME in the build's temporary directory. Every mod is
  # checked before the build fails, so one run reports them all.
  mkdir "$TMPDIR/home" "$TMPDIR/mods"
  checkFailed=
  for modPath in ${modSources}/mods/*/; do
    mod=''${modPath%/}
    mod=''${mod##*/}
    cp -RL "$modPath" "$TMPDIR/mods/$mod"
    chmod -R u+w "$TMPDIR/mods/$mod"
    if ! output=$(HOME=$TMPDIR/home ${herdr-app}/bin/herdr-app check "$TMPDIR/mods/$mod" 2>&1); then
      printf 'herdr-app mod %s in modules/home/terminal/herdr-app/mods fails herdr-app check:\n%s\n' "$mod" "$output" >&2
      checkFailed=1
    fi
  done
  if [[ -n $checkFailed ]]; then
    exit 1
  fi

  touch $out
''
