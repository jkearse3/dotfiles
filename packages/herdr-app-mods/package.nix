# The personal herdr-app mods as the herdr-app home module deploys them, one
# folder per mod in `modules/home/terminal/herdr-app/mods`, built only when
# every mod type-checks, strips to JavaScript with its source positions intact,
# and loads in the pinned app, and the mods' links to their shared code in
# `mod-lib` follow the rules below.
#
# A mod imports shared code as `./<file>`, because the app refuses imports
# that leave a mod's own folder (gpui-kit `engine/quickjs/mod.rs`,
# `AppModules`'s `Resolver::resolve`). Each such file in a mod folder is a
# relative link to `../../mod-lib/<file>`, and each output folder holds the
# link's target in its place. The link rules keep that layout: a mod file
# named like a `mod-lib` file is exactly that link, a mod folder holds no other
# link, no link dangles, and every `mod-lib` file reaches at least one mod.
#
# The build then:
# 1. rejects JavaScript sources (`.js`, `.mjs`, `.cjs`), because every mod and
#    `mod-lib` file is written in TypeScript and the deployed `.js` files are
#    built from it, and rejects `.d.ts` sources, which stripping would turn
#    into `.d.js` modules;
# 2. runs `tsc -p tsconfig.json` over the sources with `.herdr-app-types`
#    linked to herdr-app-mod-types, as the dev shell links it, and fails on
#    any diagnostic;
# 3. copies each mod with its links resolved, drops the typings the app
#    writes into a mod folder it loads (`gpui-kit.d.ts`, `jsconfig.json`),
#    and turns each `x.ts` into `x.js` by replacing its types with spaces
#    (Node's `module.stripTypeScriptTypes` in strip mode), so a runtime error
#    in the deployed file names the line and column of the `.ts` source;
# 4. strips a probe mod that throws at known positions and fails unless
#    `herdr-app check` reports those positions, so a stripper that moves code
#    fails here rather than misleading a runtime error;
# 5. runs `herdr-app check` on each built mod, so a missing shared file or an
#    import of a name the app does not export fails here.
#
# This is a package rather than only part of the home build because
# `nix flake check` builds no home configuration, and it builds this package.
# The herdr-app home module's deploy tree copies the mods from this output, so
# a failing mod also fails the switch.
{
  herdr-app,
  herdr-app-mod-types,
  modSources,
  nodejs,
  pkgs,
  typescript,
}:
let
  # Turns every `x.ts` under a built mod folder into `x.js` and deletes the
  # `.ts`. Usage: `node strip-mod-types.mjs <built mod folder> <source path>`,
  # where the source path names the mod folder in errors. Stripping replaces
  # each type with spaces, so the script fails unless the output has the
  # source's length and its newlines at the same offsets.
  # It lives here rather than in a committed file so the formatter cannot
  # reflow it.
  stripModTypes = pkgs.writeText "strip-mod-types.mjs" ''
    import { readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
    import { stripTypeScriptTypes } from "node:module";
    import { join } from "node:path";

    const [builtModDir, sourceModDir] = process.argv.slice(2);

    let failed = false;
    const tsPaths = readdirSync(builtModDir, { recursive: true })
      .filter((path) => path.endsWith(".ts"))
      .sort();
    for (const tsPath of tsPaths) {
      const sourcePath = `''${sourceModDir}/''${tsPath}`;
      const jsPath = `''${tsPath.slice(0, -".ts".length)}.js`;
      const typeScript = readFileSync(join(builtModDir, tsPath), "utf8");
      let javaScript;
      try {
        javaScript = stripTypeScriptTypes(typeScript, { mode: "strip" });
      } catch (error) {
        console.error(`''${sourcePath} cannot be stripped to JavaScript: ''${error.message}`);
        failed = true;
        continue;
      }
      if (!keepsPositions(typeScript, javaScript)) {
        console.error(`''${sourcePath} strips to JavaScript with different length or line breaks, so runtime errors would name wrong positions`);
        failed = true;
        continue;
      }

      writeFileSync(join(builtModDir, jsPath), javaScript);
      rmSync(join(builtModDir, tsPath));
    }
    process.exitCode = failed ? 1 : 0;

    function keepsPositions(typeScript, javaScript) {
      if (typeScript.length !== javaScript.length) {
        return false;
      }
      for (let offset = 0; offset < typeScript.length; offset++) {
        if ((typeScript[offset] === "\n") !== (javaScript[offset] === "\n")) {
          return false;
        }
      }
      return true;
    }
  '';
  stripModTypesCommand = "${nodejs}/bin/node --disable-warning=ExperimentalWarning ${stripModTypes}";
in
pkgs.runCommandLocal "herdr-app-mods" { } ''
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

  sourceFileFailed=
  while IFS= read -r -d "" javaScriptPath; do
    echo "modules/home/terminal/herdr-app/''${javaScriptPath#${modSources}/} is JavaScript; write it as a .ts module, which the build strips to .js" >&2
    sourceFileFailed=1
  done < <(find ${modSources}/mods ${modSources}/mod-lib '(' -name '*.js' -o -name '*.mjs' -o -name '*.cjs' ')' -print0)
  while IFS= read -r -d "" declarationPath; do
    echo "modules/home/terminal/herdr-app/''${declarationPath#${modSources}/} is a declaration file, which would deploy as a .d.js module; move its types into a .ts module and import them with import type" >&2
    sourceFileFailed=1
  done < <(find ${modSources}/mods ${modSources}/mod-lib -name '*.d.ts' -print0)
  if [[ -n $sourceFileFailed ]]; then
    exit 1
  fi

  # `tsc` runs on a writable copy that keeps the mods' links, with
  # `.herdr-app-types` where the dev shell links it, so it checks exactly the
  # project an editor sees.
  cp -R ${modSources} "$TMPDIR/src"
  chmod -R u+w "$TMPDIR/src"
  ln -s ${herdr-app-mod-types} "$TMPDIR/src/.herdr-app-types"
  if ! output=$(cd "$TMPDIR/src" && ${typescript}/bin/tsc -p tsconfig.json --pretty false 2>&1); then
    printf 'herdr-app mods in modules/home/terminal/herdr-app fail tsc -p tsconfig.json:\n%s\n' "$output" >&2
    exit 1
  fi

  # Each mod is built with its links resolved, without the app's typings, and
  # with its TypeScript stripped to JavaScript. Every mod is stripped before
  # the build fails, so one run reports them all.
  mkdir "$TMPDIR/built" "$TMPDIR/checked" "$TMPDIR/home"
  stripFailed=
  for modPath in ${modSources}/mods/*/; do
    mod=''${modPath%/}
    mod=''${mod##*/}

    cp -RL "$modPath" "$TMPDIR/built/$mod"
    chmod -R u+w "$TMPDIR/built/$mod"
    rm -f "$TMPDIR/built/$mod/gpui-kit.d.ts" "$TMPDIR/built/$mod/jsconfig.json"
    if ! ${stripModTypesCommand} "$TMPDIR/built/$mod" "modules/home/terminal/herdr-app/mods/$mod"; then
      stripFailed=1
    fi
  done
  if [[ -n $stripFailed ]]; then
    exit 1
  fi

  # The probe's lib frame is reported at its `function` keyword and its main
  # frame at the call, both after types on the same line, so stripping that
  # moved code would change the reported columns.
  probe=$TMPDIR/probe/position
  mkdir -p "$probe"
  cat > "$probe/mod.json" <<'EOF'
  { "place": "none", "title": "Position probe" }
  EOF
  cat > "$probe/lib.ts" <<'EOF'
  export type Count = number;
  const digits: number = 2; export function format(count: Count): string { return (count as Count).toFixed(digits); }
  EOF
  cat > "$probe/main.ts" <<'EOF'
  import { View, div } from "gpui-kit";
  import { format, type Count } from "./lib.js";

  export default class PositionProbe extends View {
    render() {
      return div();
    }
  }

  const missing: Count = null as unknown as Count; format(missing);
  EOF
  ${stripModTypesCommand} "$probe" "the position probe"
  probeOutput=$(HOME=$TMPDIR/home ${herdr-app}/bin/herdr-app check "$probe" 2>&1 || true)
  if ! grep -Eq '/lib\.js(\?[^:)]*)?:2:34\)' <<< "$probeOutput" ||
    ! grep -Eq '/main\.js(\?[^:)]*)?:10:57\)' <<< "$probeOutput"; then
    printf 'herdr-app-mods: the stripped position probe did not report lib.js:2:34 and main.js:10:57, so stripping moves code and runtime errors in deployed mods would name wrong positions; herdr-app check reported:\n%s\n' "$probeOutput" >&2
    exit 1
  fi

  # `check` writes typings into the folder it checks and state under `$HOME`,
  # so it runs on a scratch copy of each built mod with HOME in the build's
  # temporary directory. Every mod is checked before the build fails, so one
  # run reports them all.
  checkFailed=
  for builtPath in "$TMPDIR/built"/*/; do
    mod=''${builtPath%/}
    mod=''${mod##*/}

    cp -R "$TMPDIR/built/$mod" "$TMPDIR/checked/$mod"
    if ! output=$(HOME=$TMPDIR/home ${herdr-app}/bin/herdr-app check "$TMPDIR/checked/$mod" 2>&1); then
      printf 'herdr-app mod %s in modules/home/terminal/herdr-app/mods fails herdr-app check:\n%s\n' "$mod" "$output" >&2
      checkFailed=1
    fi
  done
  if [[ -n $checkFailed ]]; then
    exit 1
  fi

  mkdir $out
  cp -R "$TMPDIR/built"/. $out/
''
