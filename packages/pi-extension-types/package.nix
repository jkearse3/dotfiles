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
{
  nodejs,
  pi,
  pkgs,
}:
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

    # A silently empty or partial tree would leave `tsc` reporting TS2307 for
    # every pi import, which reads like an editor misconfiguration rather than a
    # build failure. Fail here instead.
    if [[ ! -f "$root/dist/index.d.ts" ]]; then
      echo "pi-extension-types: no declarations at $root/dist/index.d.ts" >&2
      echo "pi ${pi.version} may have changed its published layout" >&2
      exit 1
    fi
  ''
