{
  pkgs,
  lib,
  dockerConfig,
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
  dockerEnv = # bash
    ''
      if [[ -n "''${DOCKER_CONTEXT+x}" && -z "''${DOCKER_CONFIG+x}" ]]; then
        echo "nono-wrapper: DOCKER_CONTEXT requires an accessible DOCKER_CONFIG" >&2
        exit 2
      fi
      if [[ -z "''${DOCKER_CONFIG+x}" ]]; then
        export DOCKER_CONFIG="${dockerConfig}"
        if [[ -z "''${DOCKER_HOST+x}" && -S "$HOME/.docker/run/docker.sock" ]]; then
          export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"
        fi
      fi
      if [[ -z "''${BUILDX_CONFIG+x}" ]]; then
        BUILDX_CONFIG="$(mktemp -d "''${TMPDIR:-/tmp}/nono-buildx.XXXXXX")"
        export BUILDX_CONFIG
      fi
    '';
  scriptBody = # bash
    ''
      #!${pkgs.runtimeShell} -e
      nono_bin="${lib.getBin pkgs.nono}/bin/nono"
      cwd_flag=${lib.optionalString allowCwd "--allow-cwd"}
      cmd_prefix=${lib.optionalString (command != null) "${command}"}

      if [[ -n "$NONO_WRAPPER_DISABLE" ]]; then
        exec ${lib.optionalString (command != null) "${command} "}"$@"
      fi

      # Keep Docker usable without directly granting its host config. Custom contexts require a
      # caller-provided config because their metadata remains outside the sandbox.
      ${dockerEnv}

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
    inherit dockerEnv scriptBody;
    passAsFile = [
      "dockerEnv"
      "scriptBody"
    ];
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
    grep -q 'DOCKER_CONFIG' "$wrapper" \
      || { echo "FAIL: missing isolated Docker configuration" >&2; exit 1; }
    grep -q 'BUILDX_CONFIG' "$wrapper" \
      || { echo "FAIL: missing writable Buildx configuration" >&2; exit 1; }
    grep -q '\.docker/run/docker\.sock' "$wrapper" \
      || { echo "FAIL: missing Docker Desktop socket selection" >&2; exit 1; }

    test_root="$TMPDIR/docker-env-tests"
    mkdir -p "$test_root/home" "$test_root/tmp"

    run_default() (
      export HOME="$test_root/home" TMPDIR="$test_root/tmp"
      unset DOCKER_CONFIG DOCKER_CONTEXT DOCKER_HOST BUILDX_CONFIG
      source "$dockerEnvPath"
      [[ "$DOCKER_CONFIG" == "${dockerConfig}" ]]
      [[ -d "$BUILDX_CONFIG" ]]
      printf '%s' "$BUILDX_CONFIG"
    )

    first_buildx="$(run_default)"
    second_buildx="$(run_default)"
    [[ "$first_buildx" != "$second_buildx" ]] \
      || { echo "FAIL: Buildx state is not private per wrapper" >&2; exit 1; }

    (
      export DOCKER_CONFIG=/custom/docker BUILDX_CONFIG=/custom/buildx
      export DOCKER_HOST=unix:///custom/docker.sock
      unset DOCKER_CONTEXT
      source "$dockerEnvPath"
      [[ "$DOCKER_CONFIG" == /custom/docker ]]
      [[ "$BUILDX_CONFIG" == /custom/buildx ]]
      [[ "$DOCKER_HOST" == unix:///custom/docker.sock ]]
    ) || { echo "FAIL: explicit Docker environment was overridden" >&2; exit 1; }

    if (
      export DOCKER_CONTEXT=desktop-linux
      unset DOCKER_CONFIG BUILDX_CONFIG
      source "$dockerEnvPath"
    ) 2>/dev/null; then
      echo "FAIL: DOCKER_CONTEXT without DOCKER_CONFIG was accepted" >&2
      exit 1
    fi
  ''
