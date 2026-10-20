{
  agentInteractiveDenied,
  lib,
  pkgs,
}:
let
  denied = lib.getExe agentInteractiveDenied;

  gitAskpass = pkgs.writeShellApplication {
    name = "agent-git-askpass-denied";
    text = ''
      exec ${denied} git askpass "$@"
    '';
  };

  sshAskpass = pkgs.writeShellApplication {
    name = "agent-ssh-askpass-denied";
    text = ''
      exec ${denied} ssh askpass "$@"
    '';
  };

  jjPolicyConfig = {
    "ui.diff-editor" = [
      denied
      "jj"
      "diff-editor"
    ];
    "ui.merge-editor" = [
      denied
      "jj"
      "merge-editor"
    ];
    # Other workspaces' working-copy commits, except those built on this
    # workspace's own stack, which stays mutable when another workspace
    # stacks on it.
    "revset-aliases.\"foreign_working_copies()\"" =
      "working_copies() ~ @ ~ (builtin_immutable_heads()..@)::";
    # Makes those commits and their ancestors immutable, so a broad revset
    # such as `trunk()::` cannot rewrite or abandon another workspace's stack.
    # This replaces any repository-level definition in agent sessions.
    "revset-aliases.\"immutable_heads()\"" = "builtin_immutable_heads() | foreign_working_copies()";
    # jj runs `git` subprocesses for push and fetch, found through PATH by
    # default; the absolute path keeps agent jj's git independent of which
    # `git` comes first on PATH.
    "git.executable-path" = lib.getExe pkgs.git;
  };

  jjShim = pkgs.writeShellApplication {
    name = "jj";
    text = ''
      # `--ignore-immutable` lifts the protection of trunk and of other
      # workspaces' stacks, so it needs the user's explicit authorization.
      for argument in "$@"; do
        [[ $argument == -- ]] && break
        if [[ $argument == --ignore-immutable && ''${JJ_AGENT_ALLOW_IGNORE_IMMUTABLE-} != 1 ]]; then
          echo "jj (agent policy): --ignore-immutable is blocked in a coding-agent session; it requires the user's explicit authorization for this command." >&2
          exit 1
        fi
      done
      exec ${lib.getExe pkgs.jujutsu} ${
        lib.concatMapStringsSep " " (
          name: "--config ${lib.escapeShellArg "${name}=${builtins.toJSON jjPolicyConfig.${name}}"}"
        ) (builtins.attrNames jjPolicyConfig)
      } "$@"
    '';
  };

  gitShim = pkgs.writeShellApplication {
    name = "git";
    text = ''
      # Agents publish through `jj git push`, which runs the Nix git directly
      # through `git.executable-path`; a direct `git push` needs the user's
      # explicit authorization. Any global option the scan does not recognize
      # ends it, so only an unambiguous `push` subcommand is blocked.
      subcommand=
      arguments=("$@")
      index=0
      while ((index < ''${#arguments[@]})); do
        argument=''${arguments[index]}
        case $argument in
        -C | -c | --git-dir | --work-tree | --namespace | --config-env | --attr-source)
          ((index + 1 < ''${#arguments[@]})) || break
          index=$((index + 2))
          ;;
        --git-dir=* | --work-tree=* | --namespace=* | --config-env=* | --attr-source=* | --exec-path | --exec-path=* | \
          -p | -P | --paginate | --no-pager | --bare | --no-replace-objects | \
          --literal-pathspecs | --glob-pathspecs | --noglob-pathspecs | --icase-pathspecs | --no-optional-locks)
          index=$((index + 1))
          ;;
        -*)
          break
          ;;
        *)
          subcommand=$argument
          break
          ;;
        esac
      done

      if [[ $subcommand == push && ''${GIT_AGENT_ALLOW_PUSH-} != 1 ]]; then
        echo "git (agent policy): \`git push\` is blocked in a coding-agent session; publish with \`jj git push\`. A direct git push requires the user's explicit authorization for this command (GIT_AGENT_ALLOW_PUSH=1)." >&2
        exit 1
      fi
      exec ${lib.getExe pkgs.git} "$@"
    '';
  };

  cat = lib.getExe' pkgs.coreutils "cat";

  environment = {
    JJ_EDITOR = "${denied} jj editor";
    GIT_EDITOR = "${denied} git editor";
    GIT_SEQUENCE_EDITOR = "${denied} git sequence-editor";
    GIT_ASKPASS = lib.getExe gitAskpass;
    SSH_ASKPASS = lib.getExe sshAskpass;
    SSH_ASKPASS_REQUIRE = "force";
    GIT_TERMINAL_PROMPT = "0";
    JJ_PAGER = cat;
    GIT_PAGER = cat;
    PAGER = cat;
  };

  path = lib.makeBinPath [
    gitShim
    jjShim
    agentInteractiveDenied
  ];

  shellExports = ''
    export PATH=${lib.escapeShellArg path}:"$PATH"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") environment
    )}
  '';

  probe = pkgs.writeShellApplication {
    name = "agent-interactive-policy-probe";
    text = ''
      ${shellExports}
      exec "$@"
    '';
  };

  check =
    pkgs.runCommandLocal "agent-interactive-policy-checked"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.git
          pkgs.gnugrep
          pkgs.jujutsu
          pkgs.openssh
          pkgs.python3
        ];
      }
      ''
        ${pkgs.bash}/bin/bash ${./interactive-policy-test.sh} \
          ${denied} \
          ${lib.getExe jjShim} \
          ${lib.getExe probe} \
          ${lib.getExe gitAskpass} \
          ${lib.getExe sshAskpass} \
          ${lib.getExe pkgs.jujutsu} \
          ${cat} \
          ${lib.getExe pkgs.python3} \
          ${lib.getExe' pkgs.openssh "ssh-add"} \
          ${lib.getExe' pkgs.openssh "ssh-agent"} \
          ${lib.getExe' pkgs.openssh "ssh-keygen"} \
          ${lib.getExe pkgs.git} \
          ${lib.getExe gitShim}
        touch "$out"
      '';
in
{
  inherit
    check
    environment
    gitShim
    jjShim
    shellExports
    ;
}
