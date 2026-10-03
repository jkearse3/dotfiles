# Gate for the pi extension sources: this builds only when every extension
# typechecks and passes its fixtures.
#
# The typecheck is also what keeps an extension from importing a module pi
# cannot load. It resolves imports against exactly what an extension has at
# load: the modules pi provides, mapped by `pi-extension-types`, and the npm
# packages built from the extensions' lockfile.
#
# Pi reads extensions through a symlink into the checkout, so no other
# derivation looks at their contents. Home Manager links this one into each
# generation, which makes a failing check fail the switch. Building the package
# on its own runs the same check against the current tree.
{
  extensions,
  nodejs,
  pi-extension-deps,
  pi-extension-types,
  pkgs,
  typescript,
}:
pkgs.runCommandLocal "pi-extensions-checked"
  {
    nativeBuildInputs = [
      nodejs
      typescript
    ];
  }
  ''
    # An extension is a directory holding an `index.ts`. With none declared
    # there is nothing to check, and every step below would fail on the empty
    # tree.
    shopt -s nullglob
    entryPoints=(${extensions}/*/index.ts)
    shopt -u nullglob
    if [[ ''${#entryPoints[@]} -eq 0 ]]; then
      echo "pi-extensions-checked: no pi extensions declared"
      touch $out
      exit 0
    fi

    # Lay the sources out as a checkout has them: runtime packages under
    # `node_modules`, where npm writes them, and pi's declarations under
    # `.pi-types`, where `tsconfig.json` looks for them. Keeping the two apart
    # stops npm replacing pi's types and stops declarations passing for runtime
    # packages.
    cp -R ${extensions} ./extensions
    chmod u+w ./extensions
    ln -s ${pi-extension-deps}/node_modules ./extensions/node_modules
    ln -s ${pi-extension-types} ./extensions/.pi-types

    echo "Checking TypeScript types..."
    tsc -p ./extensions

    # A passing typecheck must mean pi can load every import, so it has to
    # reject a module pi does not provide even when pi's own tree carries
    # declarations for it. Probe one specifier of each kind.
    unresolvableSpecifiers=(
      # Declared under `@types` in pi's tree.
      semver
      # A runtime dependency of pi itself.
      chalk
      # A subpath pi's module table does not list.
      @earendil-works/pi-ai/models
      # The pre-rename spelling pi still aliases for older extensions.
      @mariozechner/pi-tui
    )
    mkdir ./extensions/unresolvable-import-probe
    for index in "''${!unresolvableSpecifiers[@]}"; do
      echo "import * as probe$index from \"''${unresolvableSpecifiers[index]}\";"
    done > ./extensions/unresolvable-import-probe/index.ts
    probeOutput="$(tsc -p ./extensions || true)"
    for specifier in "''${unresolvableSpecifiers[@]}"; do
      if ! grep -Fq "error TS2307: Cannot find module '$specifier'" <<< "$probeOutput"; then
        echo "pi-extensions-checked: tsc resolved \"$specifier\", which pi cannot load for an extension" >&2
        exit 1
      fi
    done
    rm -r ./extensions/unresolvable-import-probe

    # Node strips types natively, so the fixtures run straight from source with
    # no build step. An empty match would make this step silently vacuous.
    echo "Running pi extension fixtures..."
    readarray -t -d "" extensionTests < <(
      find ./extensions -name '*.test.ts' -type f -print0 | sort -z
    )
    if [[ ''${#extensionTests[@]} -eq 0 ]]; then
      echo "pi-extensions-checked: no extension fixtures found" >&2
      exit 1
    fi
    node --test "''${extensionTests[@]}"

    touch $out
  ''
