{
  herdr,
  jjx,
  jujutsu,
  pkgs,
}:
let
  pluginId = "dotfiles.jj-workspaces";
  runtimeInputs = [
    jjx
    pkgs.coreutils
    pkgs.jq
  ];
  addWorkspace = pkgs.writeShellApplication {
    name = "herdr-jj-workspace-add";
    inherit runtimeInputs;
    text = builtins.readFile ./add-workspace.sh;
  };
  removeWorkspace = pkgs.writeShellApplication {
    name = "herdr-jj-workspace-remove";
    inherit runtimeInputs;
    text = builtins.readFile ./remove-workspace.sh;
  };
  openPopup = pkgs.writeShellApplication {
    name = "herdr-jj-workspace-open-popup";
    text = builtins.readFile ./open-popup.sh;
  };
  # Records each call; answers worktree list with $HERDR_STUB_SOURCE, or fails
  # as Herdr does outside a repository when it is unset, and workspace list
  # with $HERDR_STUB_WORKSPACES.
  herdrStub = pkgs.writeShellScript "herdr-stub" ''
    printf '%s\n' "$*" >> "''${HERDR_STUB_LOG:?}"
    if [ "$1 $2" = "worktree list" ]; then
      [ -n "''${HERDR_STUB_SOURCE:-}" ] || exit 1
      printf '{"result":{"source":%s}}\n' "$HERDR_STUB_SOURCE"
    elif [ "$1 $2" = "workspace list" ]; then
      printf '%s\n' "''${HERDR_STUB_WORKSPACES:-}"
    fi
  '';
  manifest = (pkgs.formats.toml { }).generate "herdr-plugin.toml" {
    id = pluginId;
    name = "jj workspaces";
    version = "0.1.0";
    min_herdr_version = "0.9.3";
    description = "Create and remove jj workspaces as Herdr worktree workspaces";
    platforms = [
      "linux"
      "macos"
    ];

    actions = [
      {
        id = "add";
        title = "New jj workspace";
        contexts = [ "workspace" ];
        command = [
          "${openPopup}/bin/herdr-jj-workspace-open-popup"
          "add-prompt"
        ];
      }
      {
        id = "remove";
        title = "Remove jj workspace";
        contexts = [ "workspace" ];
        command = [
          "${openPopup}/bin/herdr-jj-workspace-open-popup"
          "remove-prompt"
        ];
      }
    ];

    panes = [
      {
        id = "add-prompt";
        title = "New jj workspace";
        placement = "popup";
        width = 72;
        height = 16;
        command = [ "${addWorkspace}/bin/herdr-jj-workspace-add" ];
      }
      {
        id = "remove-prompt";
        title = "Remove jj workspace";
        placement = "popup";
        width = 72;
        height = 16;
        command = [ "${removeWorkspace}/bin/herdr-jj-workspace-remove" ];
      }
    ];
  };
in
pkgs.runCommand "herdr-jj-workspaces-plugin"
  {
    nativeBuildInputs = [
      herdr
      jjx
      jujutsu
      pkgs.git
      pkgs.jq
    ];
    passthru = { inherit pluginId; };
  }
  ''
    install -Dm644 ${manifest} "$out/herdr-plugin.toml"

    test_root="$(mktemp -d)"
    trap 'rm -rf "$test_root"' EXIT
    mkdir -p "$test_root/home" "$test_root/config" "$test_root/data" "$test_root/runtime"
    install -Dm644 /dev/null "$test_root/gitconfig"
    export HOME="$test_root/home"
    export XDG_CONFIG_HOME="$test_root/config"
    export XDG_DATA_HOME="$test_root/data"
    export XDG_RUNTIME_DIR="$test_root/runtime"
    export GIT_CONFIG_GLOBAL="$test_root/gitconfig"
    export GIT_CONFIG_NOSYSTEM=1
    export JJ_USER="Test User" JJ_EMAIL="test@example.com"
    export HERDR_BIN_PATH="${herdrStub}" HERDR_STUB_LOG="$test_root/herdr.log"

    repo="$test_root/repo"
    git init --initial-branch=main "$repo" > /dev/null
    : > "$repo/tracked"
    (cd "$repo" && jj git init --colocate > /dev/null 2>&1 && jj commit -m initial > /dev/null 2>&1)
    context="$(jq -cn --arg repo "$repo" \
      '{ workspace_id: "w1", worktree: { repo_root: $repo, repo_name: "repo", checkout_path: $repo, is_linked_worktree: false } }')"
    HERDR_STUB_SOURCE="$(jq -cn --arg repo "$repo" '{ repo_root: $repo, repo_name: "repo" }')"
    export HERDR_STUB_SOURCE

    # Adding asks Herdr for the workspace's repository, creates the workspace
    # under Herdr's worktree directory, and opens it grouped under the current one.
    workspace="$HOME/.herdr/worktrees/repo/feature"
    printf 'feature\n' | HERDR_PLUGIN_CONTEXT_JSON="$context" ${addWorkspace}/bin/herdr-jj-workspace-add > /dev/null 2>&1
    test -f "$workspace/.jj/repo"
    jj -R "$repo" workspace list -T 'name ++ "\n"' | grep -qx feature
    test "$(<"$HERDR_STUB_LOG")" = "worktree list --workspace w1
    worktree open --workspace w1 --path $workspace --focus"
    # The workspace starts from trunk, not from the primary checkout's unfinished @.
    test "$(jj -R "$repo" log --no-graph -r 'feature@-' -T commit_id)" = "$(jj -R "$repo" log --no-graph -r 'trunk()' -T commit_id)"
    test "$(jj -R "$repo" log --no-graph -r 'feature@-' -T commit_id)" != "$(jj -R "$repo" log --no-graph -r 'default@-' -T commit_id)"

    # A workspace Herdr cannot place in a repository fails without touching jj.
    : > "$HERDR_STUB_LOG"
    if printf 'outside\n\n' | HERDR_STUB_SOURCE= HERDR_PLUGIN_CONTEXT_JSON="$context" ${addWorkspace}/bin/herdr-jj-workspace-add > /dev/null 2>&1; then
      exit 1
    fi
    test "$(<"$HERDR_STUB_LOG")" = "worktree list --workspace w1"
    test ! -e "$HOME/.herdr/worktrees/repo/outside"

    # An invalid or existing name fails without touching jj or Herdr.
    for name in ../escape feature; do
      : > "$HERDR_STUB_LOG"
      if printf '%s\n\n' "$name" | HERDR_PLUGIN_CONTEXT_JSON="$context" ${addWorkspace}/bin/herdr-jj-workspace-add > /dev/null 2>&1; then
        exit 1
      fi
      test "$(<"$HERDR_STUB_LOG")" = "worktree list --workspace w1"
    done
    test "$(jj -R "$repo" workspace list -T 'name ++ "\n"' | wc -l)" -eq 2

    workspace_context="$(jq -cn --arg repo "$repo" --arg checkout "$workspace" \
      '{ workspace_id: "w2", worktree: { repo_root: $repo, repo_name: "repo", checkout_path: $checkout, is_linked_worktree: true } }')"

    # Declining removal changes nothing.
    : > "$HERDR_STUB_LOG"
    printf 'n\n' | HERDR_PLUGIN_CONTEXT_JSON="$workspace_context" ${removeWorkspace}/bin/herdr-jj-workspace-remove > /dev/null 2>&1
    test -d "$workspace"
    test ! -s "$HERDR_STUB_LOG"

    # The primary checkout is not a removable jj workspace.
    if printf 'y\n\n' | HERDR_PLUGIN_CONTEXT_JSON="$context" ${removeWorkspace}/bin/herdr-jj-workspace-remove > /dev/null 2>&1; then
      exit 1
    fi
    test -d "$repo/.jj"

    # Confirming removal deletes the workspace, closes its Herdr workspace, and
    # focuses the workspace showing the repository's primary checkout.
    HERDR_STUB_WORKSPACES="$(jq -cn --arg repo "$repo" --arg checkout "$workspace" '{ result: { workspaces: [
      { workspace_id: "w9", worktree: { repo_root: "/elsewhere", is_linked_worktree: false } },
      { workspace_id: "w2", worktree: { repo_root: $repo, checkout_path: $checkout, is_linked_worktree: true } },
      { workspace_id: "w1", worktree: { repo_root: $repo, checkout_path: $repo, is_linked_worktree: false } }
    ] } }')"
    export HERDR_STUB_WORKSPACES
    : > "$HERDR_STUB_LOG"
    printf 'y\n' | HERDR_PLUGIN_CONTEXT_JSON="$workspace_context" ${removeWorkspace}/bin/herdr-jj-workspace-remove > /dev/null 2>&1
    test ! -e "$workspace"
    test "$(jj -R "$repo" workspace list -T 'name ++ "\n"')" = default
    test "$(<"$HERDR_STUB_LOG")" = "workspace list
    workspace close w2
    workspace focus w1"

    unset HERDR_BIN_PATH
    herdr plugin link "$out" --enabled > /dev/null
    herdr plugin list --json | jq -e --arg plugin_id "${pluginId}" \
      'any(.result.plugins[]; .plugin_id == $plugin_id and .enabled == true)' > /dev/null
  ''
