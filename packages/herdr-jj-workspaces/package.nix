{
  herdr,
  jjx,
  jujutsu,
  pkgs,
}:
let
  pluginId = "dotfiles.jj-workspaces";
  cli = pkgs.python3Packages.buildPythonApplication {
    pname = "herdr-jj-workspace";
    version = "0.0.0";
    pyproject = true;

    src = ./.;
    build-system = [ pkgs.python3Packages.setuptools ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    nativeCheckInputs = [
      jjx
      jujutsu
      pkgs.git
    ];

    postFixup = ''
      wrapProgram "$out/bin/herdr-jj-workspace" --prefix PATH : "${pkgs.lib.makeBinPath [ jjx ]}"
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      HERDR_JJ_WORKSPACE="$out/bin/herdr-jj-workspace" \
        python3 -B -m unittest discover -s tests -p 'test_*.py'
      for command in add remove; do
        "$out/bin/herdr-jj-workspace" "$command" --help > /dev/null
      done
      runHook postInstallCheck
    '';
  };
  command = subcommand: [
    "${cli}/bin/herdr-jj-workspace"
    subcommand
  ];
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
        command = command "open-popup" ++ [ "add-prompt" ];
      }
      {
        id = "remove";
        title = "Remove jj workspace";
        contexts = [ "workspace" ];
        command = command "open-popup" ++ [ "remove-prompt" ];
      }
    ];

    panes = [
      {
        id = "add-prompt";
        title = "New jj workspace";
        placement = "popup";
        width = 72;
        height = 16;
        command = command "prompt-add";
      }
      {
        id = "remove-prompt";
        title = "Remove jj workspace";
        placement = "popup";
        width = 72;
        height = 16;
        command = command "prompt-remove";
      }
    ];
  };
in
pkgs.runCommand "herdr-jj-workspaces-plugin"
  {
    nativeBuildInputs = [
      herdr
      pkgs.jq
    ];
    passthru = {
      inherit cli pluginId;
      skill = ./skill;
    };
  }
  ''
    install -Dm644 ${manifest} "$out/herdr-plugin.toml"

    test_root="$(mktemp -d)"
    trap 'rm -rf "$test_root"' EXIT
    mkdir -p "$test_root/home" "$test_root/config" "$test_root/data" "$test_root/runtime"
    export HOME="$test_root/home"
    export XDG_CONFIG_HOME="$test_root/config"
    export XDG_DATA_HOME="$test_root/data"
    export XDG_RUNTIME_DIR="$test_root/runtime"
    herdr plugin link "$out" --enabled > /dev/null
    herdr plugin list --json | jq -e --arg plugin_id "${pluginId}" \
      'any(.result.plugins[]; .plugin_id == $plugin_id and .enabled == true)' > /dev/null
  ''
