{
  fzf,
  herdr,
  pkgs,
}:
let
  pluginId = "dotfiles.find";
  cli = pkgs.python3Packages.buildPythonApplication {
    pname = "herdr-find";
    version = "0.0.0";
    pyproject = true;

    src = ./.;
    build-system = [ pkgs.python3Packages.setuptools ];
    nativeBuildInputs = [ pkgs.makeWrapper ];

    # fzf's key bindings and preview call back into the CLI by its store path.
    postFixup = ''
      wrapProgram "$out/bin/herdr-find" \
        --prefix PATH : "${
          pkgs.lib.makeBinPath [
            fzf
            herdr
          ]
        }" \
        --set HERDR_FIND_BIN "$out/bin/herdr-find"
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      HERDR_FIND="$out/bin/herdr-find" \
        python3 -B -m unittest discover -s tests -p 'test_*.py'
      for command in rows preview pick open-popup; do
        "$out/bin/herdr-find" "$command" --help > /dev/null
      done
      runHook postInstallCheck
    '';
  };
  command = subcommand: [
    "${cli}/bin/herdr-find"
    subcommand
  ];
  manifest = (pkgs.formats.toml { }).generate "herdr-plugin.toml" {
    id = pluginId;
    name = "find";
    version = "0.1.0";
    min_herdr_version = "0.9.3";
    description = "Find and jump to Herdr agents and workspaces";
    platforms = [
      "linux"
      "macos"
    ];

    actions = [
      {
        id = "open";
        title = "Find agent or workspace";
        contexts = [ "workspace" ];
        command = command "open-popup" ++ [ "picker" ];
      }
    ];

    panes = [
      {
        id = "picker";
        title = "Find agent or workspace";
        placement = "popup";
        width = "80%";
        height = "70%";
        command = command "pick";
      }
    ];
  };
in
pkgs.runCommand "herdr-find-plugin"
  {
    nativeBuildInputs = [
      herdr
      pkgs.jq
    ];
    passthru = {
      inherit cli pluginId;
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
