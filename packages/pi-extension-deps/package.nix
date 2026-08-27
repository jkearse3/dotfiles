# Runtime npm dependencies shared by Pi extensions.
#
# importNpmLock fetches from the integrity hashes already recorded in
# package-lock.json, so dependency updates need no second Nix hash. Install
# scripts stay disabled in both editable npm installs and this Nix build.
{
  nodejs,
  pkgs,
}:
let
  npmRoot = ../../modules/home/agents/pi/extensions;
  manifest = pkgs.lib.importJSON (npmRoot + "/package.json");

  importedNodeModules = pkgs.importNpmLock.buildNodeModules {
    inherit nodejs npmRoot;
    derivationArgs = {
      npmRebuildFlagsArray = [ "--ignore-scripts" ];
    };
  };
in
pkgs.runCommand "pi-extension-deps-${manifest.version}" { } ''
  mkdir -p $out/node_modules
  if [[ -d ${importedNodeModules}/node_modules ]]; then
    cp -R --no-preserve=mode ${importedNodeModules}/node_modules/. $out/node_modules/
  fi
''
