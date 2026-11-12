# Immutable pi extension tree that Home Manager installs at
# `~/.pi/agent/extensions`.
#
# A checkout's gitignored `node_modules` is never release input, so this builds
# a complete extension root from the same lockfile that local npm installs use.
{
  extensions,
  pi-extension-deps,
  pi-extensions-checked,
  pkgs,
}:
pkgs.runCommandLocal "pi-extension-root" { } ''
  # Depending on the check keeps a failing extension or Herdr integration
  # from producing an extension root.
  test -e ${pi-extensions-checked}

  mkdir -p $out
  cp -R ${extensions}/. $out/
  rm -rf $out/node_modules $out/.pi-types $out/herdr-agent-state.ts
  ln -s ${pi-extension-deps}/node_modules $out/node_modules
  ln -s ${pi-extensions-checked.herdrPiIntegration} $out/herdr-agent-state.ts
''
