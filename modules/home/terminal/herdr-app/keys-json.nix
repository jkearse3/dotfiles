# The merged `keys.json` the activation installs (`keysJson`), checked
# against the app's commands and mods, and the `prefix` mod's bindings
# (`prefixBindings`), both from `keys.nix`.
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
  # The build fails on an override the app would reject or silently drop at
  # runtime: an action that is not one of the app's commands (listed by
  # `herdr-app commands`, which needs no window), a `<mod>.<command>` for a
  # shipped or personal mod, `send:` or `terminal`; a `mod.open:` naming
  # neither a shipped mod nor a personal one from `./mods`.
  #
  # `keys.nix` keeps keys.json sections apart from its prefix bindings (the
  # keystroke typed in prefix mode). `ctrl-b` alone opens prefix mode, so the
  # check also fails when `global` does not bind `ctrl-b` to
  # `mod.open:prefix` or `mod:prefix` does not bind it to `prefix.ctrl-b`,
  # when any other section binds `ctrl-b` alone to another action, and on a
  # chord starting with `ctrl-b`, which could never fire.
  # The `prefix` mod reads the prefix bindings from `prefixBindings`. The
  # check validates their actions the same way, and also rejects a prefix
  # binding the mod cannot run: a key that is not one keystroke, `terminal`,
  # or a `send:` whose text is not exactly one control character
  # U+0001-U+001A (the mod types it as its ctrl- key). It also rejects a
  # prefix keystroke that the merged `global`, a `layout:` section, or
  # `mod:prefix` binds alone: the app's keymap handles that keystroke before
  # the prefix popup's key listener sees it. `ctrl-b` is exempt because
  # `mod:prefix` hands it to the mod.
  keysNix = import ./keys.nix;
  prefixBindings = pkgs.writeText "herdr-app-prefix-bindings.json" (builtins.toJSON keysNix.prefix);
  keysOverrides = pkgs.writeText "herdr-app-keys-overrides.json" (builtins.toJSON keysNix.sections);
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
          '
            def action_problem($action):
              ($action | index(":")) as $colon
              | (if $colon == null then $action else $action[:$colon] end) as $name
              | (if $colon == null then null else $action[$colon + 1:] end) as $argument
              | if $action == "terminal" or ($action | startswith("send:")) then empty
                elif $name == "mod.open" and ($argument | IN($mods[0][]) | not) then "unknown mod in \($action | tojson)"
                elif ($name | IN($commands[0][])) then empty
                elif ($name | index(".")) as $dot | $dot != null and ($name[:$dot] | IN($mods[0][])) and $name[$dot + 1:] != "" then empty
                else "unknown action \($action | tojson)"
                end;

            (
              $overrides[0] | to_entries[] | .key as $section
              | .value | to_entries[]
              | "\($section).\(.key): \(action_problem(.value))"
            ),
            (
              to_entries[] | .key as $section
              | if (.value | type) != "object" then "\($section): not an object of bindings"
                else .value | to_entries[]
                  | if (.value | type) != "string" then "\($section).\(.key): action is not a string"
                    else
                      (.key | split(" ") | map(select(. != ""))) as $strokes
                      | if $strokes == ["ctrl-b"] and $section == "mod:prefix" and .value != "prefix.ctrl-b" then "\($section).\(.key): ctrl-b in prefix mode must go to the prefix mod (prefix.ctrl-b)"
                        elif $strokes == ["ctrl-b"] and $section != "mod:prefix" and .value != "mod.open:prefix" then "\($section).\(.key): ctrl-b alone must open prefix mode (mod.open:prefix)"
                        elif ($strokes | length) > 1 and $strokes[0] == "ctrl-b" then "\($section).\(.key): a chord starting with ctrl-b can never fire, because prefix mode takes ctrl-b; add the key to the prefix bindings in keys.nix instead"
                        else empty
                        end
                    end
                end
            ),
            (
              if .global["ctrl-b"] == "mod.open:prefix" then empty
              else "global: ctrl-b is not bound to mod.open:prefix"
              end
            ),
            (
              if ."mod:prefix"["ctrl-b"] == "prefix.ctrl-b" then empty
              else "mod:prefix: ctrl-b is not bound to prefix.ctrl-b"
              end
            ),
            (
              to_entries[]
              | select(.key == "global" or (.key | startswith("layout:")) or .key == "mod:prefix")
              | .key as $section
              | select((.value | type) == "object")
              | .value | keys[]
              | select(test("\\s") | not) as $stroke
              | select($stroke != "ctrl-b" and ($prefix[0] | has($stroke)))
              | "prefix.\($stroke): \($section) also binds \($stroke), and that app binding takes the key before prefix mode sees it"
            ),
            (
              $prefix[0] | to_entries[]
              | "prefix.\(.key): \(
                  if (.key | test("^\\S+$") | not) then "not a single keystroke"
                  elif (.value | type) != "string" then "action is not a string"
                  elif .value == "terminal" then "terminal is not a prefix action"
                  elif (.value | startswith("send:")) then
                    (.value[5:] | explode) as $text
                    | if ($text | length) == 1 and $text[0] >= 1 and $text[0] <= 26 then empty
                      else "send: text must be one control character U+0001-U+001A"
                      end
                  else action_problem(.value)
                  end
                )"
            )
          ' keys.json > problems.txt
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
