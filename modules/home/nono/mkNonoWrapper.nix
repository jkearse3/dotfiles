{
  pkgs,
  lib,
  dockerConfig,
  onePasswordSocket,
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
  # --allow-cwd grants only the workspace itself, but jj and git in a linked Git worktree or a
  # secondary jj workspace also write into the main checkout's shared Git common dir and jj repo
  # dir. Grant those two dirs read-write when the launch directory is such a workspace. A main
  # checkout has a .git directory and a .jj/repo directory, so nothing is added there and no git
  # process runs. The granted dirs are the same ones a main-checkout launch already exposes through
  # its cwd grant (including .git/hooks, .git/config, and .jj/repo/config.toml), so a worktree
  # launch gains no access a main-checkout launch lacks. Resolution failures warn and skip the
  # grant instead of aborting the launch.
  sharedRepositoryGrants = # bash
    ''
      if [[ -f "$PWD/.git" ]]; then
        git_common_dir=""
        if git_common_dir="$(${lib.getExe pkgs.git} -C "$PWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
          && [[ -d "$git_common_dir" ]]; then
          nono_cmd+=("--allow" "$git_common_dir")
        else
          echo "nono-wrapper [${profile}]: warning: cannot resolve the Git common directory of $PWD; not granting it" >&2
        fi
      fi

      # .jj/repo holds a path to the shared repo dir, relative to .jj or absolute.
      if [[ -f "$PWD/.jj/repo" ]]; then
        jj_repo_pointer=""
        jj_repo_dir=""
        if jj_repo_pointer="$(<"$PWD/.jj/repo")" \
          && [[ -n "$jj_repo_pointer" ]] \
          && jj_repo_dir="$(CDPATH="" cd -- "$PWD/.jj" && CDPATH="" cd -- "$jj_repo_pointer" && pwd -P)"; then
          nono_cmd+=("--allow" "$jj_repo_dir")
        else
          echo "nono-wrapper [${profile}]: warning: $PWD/.jj/repo points to missing or unreadable '$jj_repo_pointer'; not granting it" >&2
        fi
      fi
    '';
  scriptBody = # bash
    ''
      #!${pkgs.runtimeShell} -e
      nono_bin="${lib.getBin pkgs.nono}/bin/nono"
      one_password_socket=${lib.escapeShellArg onePasswordSocket}
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
      if [[ -S "$one_password_socket" ]]; then
          nono_cmd+=("--allow-unix-socket" "$one_password_socket")
      fi
      if [[ -n "$SSH_AUTH_SOCK" && -S "$SSH_AUTH_SOCK" ]]; then
          nono_cmd+=("--allow-unix-socket" "$SSH_AUTH_SOCK")
      fi
      ${sharedRepositoryGrants}
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
    nativeBuildInputs = [
      pkgs.git
      pkgs.gnugrep
    ];
    inherit dockerEnv scriptBody sharedRepositoryGrants;
    passAsFile = [
      "dockerEnv"
      "scriptBody"
      "sharedRepositoryGrants"
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
    grep -Fq 'nono_cmd+=("--allow-unix-socket" "$one_password_socket")' "$wrapper" \
      || { echo "FAIL: missing normalized 1Password socket injection" >&2; exit 1; }
    grep -Fq 'nono_cmd+=("--allow-unix-socket" "$SSH_AUTH_SOCK")' "$wrapper" \
      || { echo "FAIL: missing ambient SSH_AUTH_SOCK injection" >&2; exit 1; }
    grep -q 'DOCKER_CONFIG' "$wrapper" \
      || { echo "FAIL: missing isolated Docker configuration" >&2; exit 1; }
    grep -q 'BUILDX_CONFIG' "$wrapper" \
      || { echo "FAIL: missing writable Buildx configuration" >&2; exit 1; }
    grep -q '\.docker/run/docker\.sock' "$wrapper" \
      || { echo "FAIL: missing Docker Desktop socket selection" >&2; exit 1; }
    grep -Fq -- '--git-common-dir' "$wrapper" \
      || { echo "FAIL: missing shared Git common dir grant" >&2; exit 1; }
    grep -Fq '.jj/repo' "$wrapper" \
      || { echo "FAIL: missing shared jj repo dir grant" >&2; exit 1; }

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

    repo_root="$TMPDIR/repo-grant-tests"
    mkdir -p "$repo_root/home"
    export HOME="$repo_root/home" GIT_CONFIG_NOSYSTEM=1
    cd "$repo_root"

    grants_in() (
      cd "$1"
      nono_cmd=()
      source "$sharedRepositoryGrantsPath"
      printf '%s\n' "''${nono_cmd[@]}"
    )
    expect_grants() {
      local workspace="$1" description="$2" actual expected
      shift 2
      actual="$(grants_in "$workspace" 2>/dev/null)" \
        || { echo "FAIL: $description: grant fragment failed" >&2; exit 1; }
      expected="$(if (($#)); then printf '%s\n' "$@"; fi)"
      [[ "$actual" == "$expected" ]] || {
        printf 'FAIL: %s\nexpected:\n%s\nactual:\n%s\n' "$description" "$expected" "$actual" >&2
        exit 1
      }
    }

    git -c init.defaultBranch=main init -q main
    git -C main -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    mkdir -p main/.jj/repo
    main_git="$(cd main/.git && pwd -P)"
    main_jj_repo="$(cd main/.jj/repo && pwd -P)"

    expect_grants main "main checkout gained grants"

    git -C main worktree add -q ../wt
    expect_grants wt "linked worktree" --allow "$main_git"

    git -C main worktree add -q --relative-paths ../wtrel
    expect_grants wtrel "linked worktree with relative paths" --allow "$main_git"

    git -C main worktree add -q ../ws
    mkdir ws/.jj
    printf '../../main/.jj/repo' > ws/.jj/repo
    expect_grants ws "secondary jj workspace" --allow "$main_git" --allow "$main_jj_repo"

    mkdir -p wt/.jj/repo
    wt_jj_repo="$(cd wt/.jj/repo && pwd -P)"
    git -C main worktree add -q ../ws2
    mkdir ws2/.jj
    printf '../../wt/.jj/repo' > ws2/.jj/repo
    expect_grants ws2 "jj workspace owned by a worktree" --allow "$main_git" --allow "$wt_jj_repo"

    git -C main worktree add -q ../wsabs
    mkdir wsabs/.jj
    printf '%s' "$main_jj_repo" > wsabs/.jj/repo
    expect_grants wsabs "absolute jj repo pointer" --allow "$main_git" --allow "$main_jj_repo"

    mkdir wt/sub
    expect_grants wt/sub "subdirectory of a worktree gained grants"

    mkdir outside
    expect_grants outside "directory outside any repository gained grants"

    mkdir -p broken/.jj
    printf 'gitdir: ../gone/.git/worktrees/x\n' > broken/.git
    printf '../../gone/.jj/repo' > broken/.jj/repo
    expect_grants broken "broken pointers gained grants"
    broken_warnings="$(grants_in broken 2>&1 >/dev/null | grep -c 'warning:' || true)"
    [[ "$broken_warnings" == 2 ]] \
      || { echo "FAIL: broken pointers produced $broken_warnings warnings, expected 2" >&2; exit 1; }

    mkdir -p empty/.jj
    : > empty/.jj/repo
    expect_grants empty "empty jj repo pointer gained grants"
    grants_in empty 2>&1 >/dev/null | grep -q 'warning:' \
      || { echo "FAIL: empty jj repo pointer did not warn" >&2; exit 1; }
  ''
