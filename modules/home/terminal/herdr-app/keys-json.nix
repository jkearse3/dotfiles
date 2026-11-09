# The merged `keys.json` the activation installs (`keysJson`), checked
# against the app's commands and mods, and the `prefix` mod's bindings and
# hints (`prefixBindings`), both from `keys.nix`.
{
  herdrApp,
  modNames,
  pkgs,
}:
let
  # The app never merges a user's keys.json with its defaults: it writes the
  # defaults only when the file is missing (herdr-app `src/keys.rs` `load`).
  # So the build merges the pinned app's defaults with `keys.nix` per
  # section, and a new upstream default arrives with the next app update.
  # `keys-check.jq` states and checks the rules for the merged keys.json and
  # the prefix bindings; the build fails on any problem it prints.
  keysNix = import ./keys.nix;
  prefixBindings = pkgs.writeText "herdr-app-prefix-bindings.json" (builtins.toJSON keysNix.prefix);
  keysOverrides = pkgs.writeText "herdr-app-keys-overrides.json" (builtins.toJSON keysNix.sections);

  # The build runs the check through this path, so failing fixtures fail the
  # build.
  checkedKeysCheck =
    pkgs.runCommandLocal "herdr-app-keys-check-checked" { nativeBuildInputs = [ pkgs.jq ]; } # bash
      ''
        bash ${./keys-check-test.sh} ${./keys-check.jq}
        ln -s ${./keys-check.jq} "$out"
      '';

  keysJson =
    pkgs.runCommandLocal "herdr-app-keys.json" { nativeBuildInputs = [ pkgs.jq ]; } # bash
      ''
        ${herdrApp}/bin/herdr-app commands > commands.json
        jq '[.[].name]' commands.json > command-names.json
        jq -s '.[0] * .[1]' ${herdrApp.src}/defaults/keys.macos.json ${keysOverrides} > keys.json

        jq -r \
          --slurpfile commands command-names.json \
          --slurpfile mods ${modNames} \
          --slurpfile overrides ${keysOverrides} \
          --slurpfile prefix ${prefixBindings} \
          -f ${checkedKeysCheck} keys.json > problems.txt
        if [ -s problems.txt ]; then
          echo "herdr-app key bindings (keys.nix) are invalid:" >&2
          cat problems.txt >&2
          exit 1
        fi
        cp keys.json $out
      '';
in
{
  inherit keysJson prefixBindings;
}
