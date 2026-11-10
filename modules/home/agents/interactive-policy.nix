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

  # Agents add a Co-authored-by trailer naming themselves out of habit, even
  # when their harness is configured to add no attribution. An agent has no
  # reason to credit anyone on its own, so the shims below refuse every
  # co-author trailer, whoever it names, rather than guess which names are AI
  # tools. Each message an agent hands jj or git passes through
  # `reject_co_author_trailer` before the real tool records it; a co-author
  # the user asked for goes through with `AGENT_ALLOW_CO_AUTHOR=1`. A message
  # is rejected only when one of its lines is such a trailer, so scanning a
  # flag value that is not a message cannot block a command. The guard catches
  # habit, not evasion: a message that reaches the tool another way, such as a
  # `-F` file the shim cannot resolve, passes unchecked.
  coAuthorGuard = ''
    # Exits with a policy error when the message on stdin carries a
    # Co-authored-by trailer. $1 names the tool for the error.
    reject_co_author_trailer() {
      if [[ ''${AGENT_ALLOW_CO_AUTHOR-} != 1 ]] &&
        ${lib.getExe pkgs.gnugrep} -qiE -- '^[[:space:]]*co-authored-by:'; then
        echo "$1 (agent policy): the commit message carries a Co-authored-by trailer. Remove it and rerun the command. A co-author the user explicitly asked for requires AGENT_ALLOW_CO_AUTHOR=1 on this command." >&2
        exit 1
      fi
    }

    # Checks the message the real tool will read from stdin, then hands it the
    # same bytes from a deleted temporary copy.
    reject_co_author_trailer_on_stdin() {
      local copy
      copy=$(${lib.getExe' pkgs.coreutils "mktemp"})
      ${cat} >"$copy"
      reject_co_author_trailer "$1" <"$copy"
      exec 0<"$copy"
      ${lib.getExe' pkgs.coreutils "rm"} -f -- "$copy"
    }
  '';

  jjShim = pkgs.writeShellApplication {
    name = "jj";
    text = ''
      ${coAuthorGuard}
      arguments=("$@")
      index=0
      while ((index < ''${#arguments[@]})); do
        argument=''${arguments[index]}
        case $argument in
        --)
          break
          ;;
        # `--ignore-immutable` lifts the protection of trunk and of other
        # workspaces' stacks, so it needs the user's explicit authorization.
        --ignore-immutable)
          if [[ ''${JJ_AGENT_ALLOW_IGNORE_IMMUTABLE-} != 1 ]]; then
            echo "jj (agent policy): --ignore-immutable is blocked in a coding-agent session; it requires the user's explicit authorization for this command." >&2
            exit 1
          fi
          ;;
        -m | --message)
          if ((index + 1 < ''${#arguments[@]})); then
            reject_co_author_trailer jj <<<"''${arguments[index + 1]}"
          fi
          index=$((index + 1))
          ;;
        -m?*)
          reject_co_author_trailer jj <<<"''${argument#-m}"
          ;;
        --message=*)
          reject_co_author_trailer jj <<<"''${argument#--message=}"
          ;;
        --stdin)
          reject_co_author_trailer_on_stdin jj
          ;;
        esac
        index=$((index + 1))
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
      ${coAuthorGuard}
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

      # Messages reach git through `-m`/`--message` on any subcommand, a short
      # option cluster ending in `m` or `F` such as `-am`, and `-F`/`--file` on
      # the subcommands where it names a message file rather than, as in
      # `git grep -F`, a matching mode. `-F -` reads the message from stdin.
      message_file_flag=
      case $subcommand in
      commit | commit-tree | merge | notes | tag) message_file_flag=1 ;;
      esac
      index=$((index + 1))
      while [[ -n $subcommand ]] && ((index < ''${#arguments[@]})); do
        argument=''${arguments[index]}
        value=''${arguments[index + 1]-}
        case $argument in
        --)
          break
          ;;
        -m | --message | -[[:alpha:]]*m)
          reject_co_author_trailer git <<<"$value"
          index=$((index + 1))
          ;;
        -m?*)
          reject_co_author_trailer git <<<"''${argument#-m}"
          ;;
        --message=*)
          reject_co_author_trailer git <<<"''${argument#--message=}"
          ;;
        -F | --file | -[[:alpha:]]*F | --file=*)
          if [[ -n $message_file_flag ]]; then
            if [[ $argument == --file=* ]]; then
              value=''${argument#--file=}
            else
              index=$((index + 1))
            fi
            if [[ $value == - ]]; then
              reject_co_author_trailer_on_stdin git
            elif [[ -f $value && -r $value ]]; then
              reject_co_author_trailer git <"$value"
            fi
          fi
          ;;
        esac
        index=$((index + 1))
      done
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
