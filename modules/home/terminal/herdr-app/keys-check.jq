# The rules for the Herdr app key bindings in `keys.nix`. `keys-json.nix`
# runs this program on the merged keys.json (the app's
# `defaults/keys.macos.json` with the `sections` of `keys.nix` merged over it
# per section) and fails the build when it prints anything: one line per
# problem, naming the section (or `prefix`) and key. Fixtures in
# `keys-check-test.sh` cover each rule.
#
# Inputs, each read with `--slurpfile`, so the value is `$name[0]`:
#
# - `$commands`: the app's command names (`herdr-app commands`, which needs
#   no window).
# - `$mods`: every mod name the app will find installed, shipped or personal
#   (from `./mods`).
# - `$overrides`: the `sections` of `keys.nix`.
# - `$prefix`: the prefix bindings, the `prefix` of `keys.nix` (the keystroke
#   typed in prefix mode, mapped to an action), which the `prefix` mod reads
#   from its `bindings.json`.
#
# The rules catch what the app would reject or silently drop at runtime:
#
# 1. Only actions `keys.nix` sets are checked against rule 2, not the app's
#    defaults; the other rules check the merged keys.json.
# 2. A valid action is `terminal`; `send:<text>`; one of the app's commands,
#    compared on the part before `:`; `<mod>.<command>` for a known mod and
#    a non-empty command; or `mod.open:<mod>` for a known mod.
# 3. Every section is an object whose actions are strings.
# 4. `ctrl-b` alone opens prefix mode, so it must be `mod.open:prefix` in
#    every section except `mod:prefix`. There it must be `prefix.ctrl-b`: the
#    open prefix mod takes it as a prefix keystroke, because that section's
#    key context is deeper than `global`'s.
# 5. A chord starting with `ctrl-b` is rejected: it could never fire,
#    because prefix mode takes `ctrl-b`.
# 6. `global` and `mod:prefix` must both bind `ctrl-b` as rule 4 says.
# 7. A prefix keystroke other than `ctrl-b` must not also be bound alone in
#    `global`, a `layout:` section, or `mod:prefix`: the app's keymap takes
#    that keystroke before the prefix popup's key listener sees it. `ctrl-b`
#    is exempt because `mod:prefix` hands it to the mod.
# 8. A prefix binding is one keystroke with a string action that the mod can
#    run: not `terminal`, and a `send:` carries exactly one control character
#    U+0001-U+001A, which the mod types as its ctrl- key. Other actions
#    follow rule 2.

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
