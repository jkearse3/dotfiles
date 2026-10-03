# Gate for the pi extension sources: this builds only when every extension
# imports modules pi can resolve, typechecks, and passes its fixtures.
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

    # The import checker parses sources with TypeScript's JavaScript API.
    NODE_PATH = "${typescript}/lib/node_modules";
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

    echo "Checking pi extension imports..."
    piModules=./extensions/.pi-types/pi-modules.json
    bash ${./extension-imports-check-test.sh} ${./extension-imports-check.mjs} "$piModules"
    node ${./extension-imports-check.mjs} ./extensions "$piModules"

    echo "Checking TypeScript types..."
    tsc -p ./extensions

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
