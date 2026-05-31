{
  pkgs,
  lib,
}:
{
  name ? null,
  profile,
  allowCwd ? true,
  command ? null,
}:
assert lib.assertMsg (profile != "") "mkNonoWrapper: profile must not be empty";
assert lib.assertMsg (
  command == null || command != ""
) "mkNonoWrapper: command must be null or non-empty";
let
  wrapperName = if name != null then name else profile;
  scriptBody = # bash
    ''
      #!${pkgs.runtimeShell} -e
      nono_bin="${lib.getBin pkgs.nono}/bin/nono"
      cwd_flag=${lib.optionalString allowCwd "--allow-cwd"}
      cmd_prefix=${lib.optionalString (command != null) "${command}"}

      if [[ -n "$NONO_WRAPPER_DISABLE" ]]; then
        exec ${lib.optionalString (command != null) "${command} "}"$@"
      fi

      # Per-repo overlay: if ./.nono/profile.json exists relative to cwd,
      # pass its absolute path to `nono run --profile` instead of the named
      # profile. nono's `extends` merging composes the overlay atop its
      # declared parent (filesystem/groups/commands additive; scalars
      # overridden; denies unioned). The shim does not parse or merge JSON.
      #
      # Sharp edge: an overlay missing `extends` collapses to a standalone
      # default-deny profile, silently breaking the sandbox. Warn on stderr.
      profile_arg="${profile}"
      overlay_path="$PWD/.nono/profile.json"
      if [[ -f "$overlay_path" ]]; then
        profile_arg="$overlay_path"
        if ! ${lib.getBin pkgs.gnugrep}/bin/grep -q '"extends"' "$overlay_path"; then
          echo "nono-wrapper [${profile}]: warning: $overlay_path has no \"extends\" key; sandbox will fall back to default-deny" >&2
        fi
      fi

      nono_cmd=(
        "$nono_bin" "wrap" "--profile" "$profile_arg"
      )
      [[ -n "$cwd_flag" ]] && nono_cmd+=("$cwd_flag")
      if [[ -n "$SSH_AUTH_SOCK" && -S "$SSH_AUTH_SOCK" ]]; then
          nono_cmd+=("--allow-unix-socket" "$SSH_AUTH_SOCK")
      fi
      nono_cmd+=("--")
      [[ -n "$cmd_prefix" ]] && nono_cmd+=("$cmd_prefix")

      if [[ -n "$NONO_WRAPPER_VERBOSE" ]]; then
        echo "nono-wrapper [${profile} -> $profile_arg]: exec ''${nono_cmd[*]} $*" >&2
      fi

      exec "''${nono_cmd[@]}" "$@"
    '';
in
pkgs.runCommandLocal "nono-${wrapperName}"
  {
    nativeBuildInputs = [ pkgs.gnugrep ];
    inherit scriptBody;
    passAsFile = [ "scriptBody" ];
  }
  ''
    wrapper="$out/bin/nono-${wrapperName}"
    mkdir -p "$(dirname "$wrapper")"
    mv "$scriptBodyPath" "$wrapper"
    chmod +x "$wrapper"

    grep -q 'NONO_WRAPPER_DISABLE' "$wrapper" \
      || { echo "FAIL: missing NONO_WRAPPER_DISABLE" >&2; exit 1; }
    grep -q 'NONO_WRAPPER_VERBOSE' "$wrapper" \
      || { echo "FAIL: missing NONO_WRAPPER_VERBOSE" >&2; exit 1; }
    grep -q 'nono.*wrap.*--profile' "$wrapper" \
      || { echo "FAIL: missing exec nono wrap pattern" >&2; exit 1; }
    grep -q '\.nono/profile\.json' "$wrapper" \
      || { echo "FAIL: missing .nono/profile.json overlay detection" >&2; exit 1; }
    grep -q 'no .*extends.* key' "$wrapper" \
      || { echo "FAIL: missing overlay missing-extends warning" >&2; exit 1; }
    grep -q 'allow-unix-socket' "$wrapper" \
      || { echo "FAIL: missing SSH_AUTH_SOCK injection" >&2; exit 1; }
  ''
