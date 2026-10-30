# Immutable pi extension tree for locked Home Manager delivery.
#
# Locked mode cannot use the editable checkout's gitignored `node_modules`, so
# this builds a complete extension root from the same lockfile used by editable
# npm installs. In editable mode the pi module's mkSource points Pi directly at
# the checkout instead, where npm owns runtime dependencies.
{
  extensions,
  pi-extension-deps,
  pi-extensions-checked,
  pkgs,
}:
pkgs.runCommandLocal "pi-extensions-locked" { } ''
  # Depending on the check keeps a failing extension or Herdr integration
  # from producing a locked tree.
  test -e ${pi-extensions-checked}

  mkdir -p $out
  cp -R ${extensions}/. $out/
  rm -rf $out/node_modules $out/.pi-types $out/herdr-agent-state.ts
  ln -s ${pi-extension-deps}/node_modules $out/node_modules
  ln -s ${pi-extensions-checked.herdrPiIntegration} $out/herdr-agent-state.ts
''
