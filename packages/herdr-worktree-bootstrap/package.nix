{
  herdr,
  jj-ensure,
  pkgs,
}:
let
  pluginId = "dotfiles.worktree-bootstrap";
  mkHook =
    jjEnsure:
    pkgs.writeShellApplication {
      name = "herdr-worktree-bootstrap";
      runtimeInputs = [
        jjEnsure
        pkgs.jq
      ];
      text = builtins.readFile ./worktree-created.sh;
    };
  hook = mkHook jj-ensure;
  failingHook = mkHook (
    pkgs.writeShellScriptBin "jj-ensure" ''
      exit 23
    ''
  );
  notificationStub = pkgs.writeShellScript "herdr-notification-stub" ''
    printf '%s\0' "$@" >> "''${HERDR_NOTIFICATION_LOG:?}"
    exit "''${HERDR_NOTIFICATION_EXIT_CODE:-0}"
  '';
  manifest = (pkgs.formats.toml { }).generate "herdr-plugin.toml" {
    id = pluginId;
    name = "worktree bootstrap";
    version = "0.1.0";
    min_herdr_version = "0.8.2";
    description = "Run best-effort setup, including jj initialization, for Herdr-created Git worktrees";
    platforms = [
      "linux"
      "macos"
    ];

    actions = [
      {
        id = "retry-bootstrap";
        title = "Retry worktree bootstrap";
        contexts = [ "workspace" ];
        command = [ "${hook}/bin/herdr-worktree-bootstrap" ];
      }
    ];

    events = [
      {
        on = "worktree.created";
        command = [ "${hook}/bin/herdr-worktree-bootstrap" ];
      }
    ];
  };
in
pkgs.runCommand "herdr-worktree-bootstrap-plugin"
  {
    nativeBuildInputs = [
      herdr
      pkgs.git
      pkgs.jq
    ];
    passthru = { inherit pluginId; };
  }
  ''
    install -Dm644 ${manifest} "$out/herdr-plugin.toml"

    test_root="$(mktemp -d)"
    trap 'rm -rf "$test_root"' EXIT
    primary="$test_root/primary"
    linked="$test_root/linked"
    mkdir -p "$test_root/home" "$test_root/config" "$test_root/data" "$test_root/runtime"
    install -Dm644 /dev/null "$test_root/gitconfig"
    export HOME="$test_root/home"
    export XDG_CONFIG_HOME="$test_root/config"
    export XDG_DATA_HOME="$test_root/data"
    export XDG_RUNTIME_DIR="$test_root/runtime"
    export GIT_CONFIG_GLOBAL="$test_root/gitconfig"
    export GIT_CONFIG_NOSYSTEM=1

    git init --initial-branch=main "$primary" > /dev/null
    git -C "$primary" config user.name "Test User"
    git -C "$primary" config user.email "test@example.com"
    : > "$primary/tracked"
    git -C "$primary" add tracked
    git -C "$primary" commit -m initial > /dev/null
    git -C "$primary" worktree add --detach "$linked" HEAD > /dev/null

    bootstrap="${hook}/bin/herdr-worktree-bootstrap"
    action_json="$(jq -cn --arg path "$linked" '{ worktree: { checkout_path: $path, is_linked_worktree: true } }')"
    HERDR_PLUGIN_CONTEXT_JSON="$action_json" "$bootstrap" > /dev/null
    test -d "$linked/.jj"
    private_git="$(git -C "$linked" rev-parse --absolute-git-dir)"
    test "$(<"$linked/.jj/repo/store/git_target")" = "$private_git"

    event_json="$(jq -cn --arg path "$linked" '{ data: { worktree: { path: $path } } }')"
    HERDR_PLUGIN_EVENT_JSON="$event_json" "$bootstrap" > /dev/null

    primary_action_json="$(jq -cn --arg path "$primary" '{ worktree: { checkout_path: $path, is_linked_worktree: false } }')"
    notification_log="$test_root/notification.log"
    set +e
    HERDR_BIN_PATH="${notificationStub}" HERDR_NOTIFICATION_LOG="$notification_log" \
      HERDR_NOTIFICATION_EXIT_CODE=73 HERDR_PLUGIN_CONTEXT_JSON="$primary_action_json" \
      "$bootstrap" > /dev/null 2>&1
    bootstrap_status=$?
    set -e
    test "$bootstrap_status" -eq 4
    mapfile -d "" -t notification_args < "$notification_log"
    test "''${#notification_args[@]}" -eq 7
    test "''${notification_args[0]}" = "notification"
    test "''${notification_args[1]}" = "show"
    test "''${notification_args[2]}" = "Worktree bootstrap failed"
    test "''${notification_args[3]}" = "--body"
    test "''${notification_args[4]}" = "Check Herdr plugin logs for details."
    test "''${notification_args[5]}" = "--sound"
    test "''${notification_args[6]}" = "request"

    missing_path_event_json='{"data":{"worktree":{}}}'
    missing_path_notification_log="$test_root/missing-path-notification.log"
    set +e
    HERDR_BIN_PATH="${notificationStub}" HERDR_NOTIFICATION_LOG="$missing_path_notification_log" \
      HERDR_PLUGIN_EVENT_JSON="$missing_path_event_json" \
      "$bootstrap" > /dev/null 2>&1
    bootstrap_status=$?
    set -e
    test "$bootstrap_status" -eq 1
    mapfile -d "" -t notification_args < "$missing_path_notification_log"
    test "''${#notification_args[@]}" -eq 7
    test "''${notification_args[4]}" = "Check Herdr plugin logs for details."

    failing_notification_log="$test_root/failing-notification.log"
    set +e
    HERDR_BIN_PATH="${notificationStub}" HERDR_NOTIFICATION_LOG="$failing_notification_log" \
      HERDR_PLUGIN_CONTEXT_JSON="$action_json" \
      "${failingHook}/bin/herdr-worktree-bootstrap" > /dev/null 2>&1
    bootstrap_status=$?
    set -e
    test "$bootstrap_status" -eq 23
    mapfile -d "" -t notification_args < "$failing_notification_log"
    expected_notification_body="Checkout: $linked"$'\n\n'"Check Herdr plugin logs for details."
    test "''${#notification_args[@]}" -eq 7
    test "''${notification_args[4]}" = "$expected_notification_body"

    herdr plugin link "$out" --disabled > /dev/null
    current_plugins="$(herdr plugin list --json)"
    if ! printf '%s' "$current_plugins" | jq -e \
      --arg plugin_id "${pluginId}" \
      --arg plugin_path "$out" \
      'any(.result.plugins[]; .plugin_id == $plugin_id and .plugin_root == $plugin_path and .enabled == true)' > /dev/null; then
      herdr plugin link "$out" --enabled > /dev/null
    fi
    current_plugins="$(herdr plugin list --json)"
    printf '%s' "$current_plugins" | jq -e \
      --arg plugin_id "${pluginId}" \
      --arg plugin_path "$out" \
      'any(.result.plugins[]; .plugin_id == $plugin_id and .plugin_root == $plugin_path and .enabled == true)' > /dev/null
  ''
