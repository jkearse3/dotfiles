# TypeScript declarations for authoring pi extensions.
#
# Both inputs are attributes of the pi package that is actually run, so the
# declarations cannot describe a different version than the binary: `pi.src` is
# the unpacked tarball carrying `dist/*.d.ts` plus the lockfile, and
# `pi.npmDeps` is the npm cache that lockfile resolves against. There is no
# second package to drift, so no version assertion is needed.
#
# `@earendil-works/pi-coding-agent` is the monorepo root rather than a
# `node_modules` entry, so it is installed from `pi.src` separately.
#
# The output also carries a `tsconfig.json`, generated from `moduleDeclarations`
# below, that maps each module an extension may import from pi to its
# declaration. The extensions' own `tsconfig.json` extends it, so `tsc` and
# editors resolve exactly those modules and no others from pi's tree.
{
  nodejs,
  pi,
  pkgs,
}:
let
  inherit (pkgs) lib;

  # Every specifier pi resolves for an extension at runtime, with the
  # declaration entry point it has under `node_modules`. This mirrors the module
  # table in pi's `dist/core/extensions/loader.js`, minus the `@mariozechner/*`
  # aliases it also carries. Those are the pre-rename spellings, kept upstream
  # so older extensions keep loading; new source here should use the current
  # names. The build compares these keys with that table's and fails, naming
  # each specifier, when they differ; the declaration paths stay hand-written.
  #
  # Pi's table carries whole specifiers, not prefixes, so each importable
  # subpath is its own entry.
  #
  # Pi resolves both the pi-ai root and `/compat` to its pi-ai extension view:
  # the compat entry plus TypeBox's `Type`, `Static` and `TSchema`, which the
  # pi-ai root no longer re-exports. Only the root maps to the view's
  # declaration here, because that declaration re-exports `/compat`; mapping
  # `/compat` to it too would make the view re-export itself. Extensions
  # importing `/compat` therefore see the compat surface without TypeBox.
  moduleDeclarations = {
    "@earendil-works/pi-agent-core" = "@earendil-works/pi-agent-core/dist/index.d.ts";
    "@earendil-works/pi-ai" =
      "@earendil-works/pi-coding-agent/dist/core/extensions/pi-ai-extension-view.d.ts";
    "@earendil-works/pi-ai/compat" = "@earendil-works/pi-ai/dist/compat.d.ts";
    "@earendil-works/pi-ai/models" = "@earendil-works/pi-ai/dist/models.d.ts";
    "@earendil-works/pi-ai/oauth" = "@earendil-works/pi-ai/dist/oauth.d.ts";
    "@earendil-works/pi-ai/providers/all" = "@earendil-works/pi-ai/dist/providers/all.d.ts";
    "@earendil-works/pi-coding-agent" = "@earendil-works/pi-coding-agent/dist/index.d.ts";
    "@earendil-works/pi-tui" = "@earendil-works/pi-tui/dist/index.d.ts";
    "@sinclair/typebox" = "typebox/build/index.d.mts";
    "@sinclair/typebox/compile" = "typebox/build/compile/index.d.mts";
    "@sinclair/typebox/value" = "typebox/build/value/index.d.mts";
    "typebox" = "typebox/build/index.d.mts";
    "typebox/compile" = "typebox/build/compile/index.d.mts";
    "typebox/value" = "typebox/build/value/index.d.mts";
  };

  # One `<specifier>\t<declaration>` line per `moduleDeclarations` entry, for
  # the build script's checks.
  moduleDeclarationsTsv = pkgs.writeText "pi-module-declarations.tsv" (
    lib.concatStrings (
      lib.mapAttrsToList (specifier: declaration: "${specifier}\t${declaration}\n") moduleDeclarations
    )
  );

  # `paths` entries resolve against the file that declares them, so the
  # extensions' own `tsconfig.json` extends this one and must not set `baseUrl`
  # or `paths` itself: either would replace these mappings rather than add to
  # them.
  tsconfig = pkgs.writeText "pi-extension-types-tsconfig.json" (
    builtins.toJSON {
      compilerOptions.paths = lib.mapAttrs (_: declaration: [
        "./node_modules/${declaration}"
      ]) moduleDeclarations;
    }
  );
in
pkgs.runCommand "pi-extension-types-${pi.version}"
  {
    nativeBuildInputs = [ nodejs ];
    passthru.piVersion = pi.version;
    meta = {
      description = "Type declarations for pi extension sources, built from the pi runtime";
    };
  }
  ''
    export HOME="$TMPDIR"
    cd "$TMPDIR"

    # Pi resolves an extension's imports through the `_aliases` table in its
    # extension loader. A specifier the table gains would fail `tsc` with TS2307,
    # and one it drops would still typecheck here but fail to load in pi, so
    # compare the table's keys with `moduleDeclarations` before installing.
    # Only `"<specifier>": <identifier>,` and `<identifier>: <identifier>,`
    # entries are understood; any other entry fails rather than being skipped.
    alias_entry='^[[:space:]]*("([^"]+)"|([A-Za-z_$][A-Za-z0-9_$]*)):[[:space:]]*[A-Za-z_$][A-Za-z0-9_$]*,?[[:space:]]*$'
    : >loader-specifiers
    while IFS= read -r line; do
      if [[ ! $line =~ $alias_entry ]]; then
        echo "pi-extension-types: cannot read this _aliases entry in pi ${pi.version}'s dist/core/extensions/loader.js: $line" >&2
        exit 1
      fi
      specifier="''${BASH_REMATCH[2]:-''${BASH_REMATCH[3]}}"
      if [[ $specifier != "@mariozechner/"* ]]; then
        echo "$specifier" >>loader-specifiers
      fi
    done < <(
      awk '
        /^[[:space:]]*_aliases = \{$/ { inside = 1; next }
        inside && /^[[:space:]]*\};/ { exit }
        inside && NF { print }
      ' ${pi.src}/dist/core/extensions/loader.js
    )
    if [[ ! -s loader-specifiers ]]; then
      echo "pi-extension-types: found no _aliases table in dist/core/extensions/loader.js; pi ${pi.version} changed its loader layout, update this check" >&2
      exit 1
    fi

    sort -u loader-specifiers -o loader-specifiers
    cut -f1 ${moduleDeclarationsTsv} | sort -u >declared-specifiers
    drift=0
    while IFS= read -r specifier; do
      echo "pi-extension-types: pi ${pi.version}'s extension loader resolves $specifier, which moduleDeclarations lacks" >&2
      drift=1
    done < <(comm -23 loader-specifiers declared-specifiers)
    while IFS= read -r specifier; do
      echo "pi-extension-types: moduleDeclarations lists $specifier, which pi ${pi.version}'s extension loader no longer resolves" >&2
      drift=1
    done < <(comm -13 loader-specifiers declared-specifiers)
    if [[ $drift -ne 0 ]]; then
      echo "update moduleDeclarations in packages/pi-extension-types/package.nix to match the _aliases table in pi's dist/core/extensions/loader.js" >&2
      exit 1
    fi

    cp ${pi.src}/package.json ${pi.src}/package-lock.json .

    # npm resolves `<cache>/_cacache`, so the cache flag must name the parent of
    # `_cacache`. Pointing it at `_cacache` itself makes every lookup fail with
    # ENOTCACHED rather than reporting a missing cache.
    cp -r ${pi.npmDeps}/_cacache ./_cacache
    chmod -R u+w ./_cacache
    npm ci --offline --ignore-scripts --no-audit --no-fund --cache="$PWD"

    # Keep declarations and the manifests that resolve them; everything else in
    # the dependency tree is runtime code pi already carries in its binary.
    mkdir -p "$out/node_modules"
    find node_modules \
      \( -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' -o -name 'package.json' \) \
      -type f -print0 |
      while IFS= read -r -d "" file; do
        install -Dm444 "$file" "$out/$file"
      done

    root="$out/node_modules/@earendil-works/pi-coding-agent"
    mkdir -p "$root"
    install -Dm444 ${pi.src}/package.json "$root/package.json"
    find ${pi.src}/dist \
      \( -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' \) \
      -type f -print0 |
      while IFS= read -r -d "" file; do
        install -Dm444 "$file" "$root/dist/''${file#${pi.src}/dist/}"
      done

    install -Dm444 ${tsconfig} "$out/tsconfig.json"

    # A missing declaration would leave `tsc` reporting TS2307 for that import,
    # which reads like an editor misconfiguration rather than a build failure.
    # Fail here instead, naming each module whose declaration moved.
    missing=0
    while IFS=$'\t' read -r specifier declaration; do
      if [[ ! -f "$out/node_modules/$declaration" ]]; then
        echo "pi-extension-types: no declaration for $specifier at node_modules/$declaration" >&2
        missing=1
      fi
    done < ${moduleDeclarationsTsv}
    if [[ $missing -ne 0 ]]; then
      echo "pi-extension-types: pi ${pi.version} may have moved a declaration in its published layout; update that specifier's declaration path in moduleDeclarations" >&2
      exit 1
    fi
  ''
