{
  agentInteractiveDenied,
  agentPolicy,
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

  # The command policy every agent's jj and git invocations pass through
  # `agent-policy`. A refused rule names its ID; the agent requests the user's
  # approval by rerunning the command with `AGENT_POLICY_APPROVE=<id>`, which
  # each agent harness turns into a prompt.
  commandPolicy = {
    tools = {
      jj = {
        executable = lib.getExe pkgs.jujutsu;
        prefix-arguments = lib.concatMap (name: [
          "--config"
          "${name}=${builtins.toJSON jjPolicyConfig.${name}}"
        ]) (builtins.attrNames jjPolicyConfig);
        # clap accepts jj's global options before, between, and after
        # subcommands.
        global-options-position = "anywhere";
        global-options = [
          {
            names = [
              "-R"
              "--repository"
            ];
            arity = "value";
          }
          {
            names = [ "--ignore-working-copy" ];
            arity = "flag";
          }
          {
            names = [ "--ignore-immutable" ];
            arity = "flag";
          }
          {
            names = [
              "--at-operation"
              "--at-op"
            ];
            arity = "value";
          }
          {
            names = [ "--debug" ];
            arity = "flag";
          }
          {
            names = [ "--color" ];
            arity = "value";
          }
          {
            names = [ "--quiet" ];
            arity = "flag";
          }
          {
            names = [ "--no-pager" ];
            arity = "flag";
          }
          {
            names = [ "--config" ];
            arity = "value";
          }
          {
            names = [ "--config-file" ];
            arity = "value";
          }
          {
            names = [ "--no-integrate-operation" ];
            arity = "flag";
          }
          {
            names = [
              "-h"
              "--help"
            ];
            arity = "flag";
          }
        ];
        rules = [
          {
            id = "jj.ignore-immutable";
            kind = "refuse-option";
            scope = "any";
            refused-options = [ "--ignore-immutable" ];
            message = "`--ignore-immutable` lifts the protection of trunk and of other workspaces' stacks; rewrite only mutable revisions of your own stack instead.";
          }
          # Pushes that name each bookmark and only add or fast-forward remote
          # bookmarks run unprompted; everything else, including force pushes
          # and deletions, needs the user's approval. Unlisted options refuse,
          # so a jj upgrade cannot widen what passes.
          {
            id = "jj.git-push";
            kind = "allowlist";
            scope = [
              "git"
              "push"
            ];
            allowed-options = [
              {
                names = [
                  "-b"
                  "--bookmark"
                ];
                arity = "value";
                value-constraint = "literal-name";
              }
              # A revset; the dry-run check bounds how many bookmarks it adds.
              {
                names = [
                  "-c"
                  "--change"
                ];
                arity = "value";
              }
              {
                names = [ "--named" ];
                arity = "value";
                value-constraint = "literal-name-before-equals";
              }
              {
                names = [ "--remote" ];
                arity = "value";
                value-constraint = "literal-name";
              }
              {
                names = [ "--dry-run" ];
                arity = "flag";
              }
            ];
            allowed-global-options = [
              "-R"
              "--quiet"
              "--no-pager"
              "--color"
              "--debug"
              "--ignore-working-copy"
              "-h"
            ];
            target-options = [
              "-b"
              "-c"
              "--named"
            ];
            informational-options = [ "-h" ];
            checks = [ "jj-push-dry-run" ];
            message = "Agents push named bookmarks forward with `jj git push -b <name>` (one `-b` per bookmark), `-c <revision>`, or `--named <name>=<revision>`, optionally with `--remote <name>` and `--dry-run`; pushes that select bookmarks by pattern or in bulk, rewrite or delete remote bookmarks, or change jj's configuration or operation are the user's decision.";
          }
        ];
      };

      git = {
        executable = lib.getExe pkgs.git;
        prefix-arguments = [ ];
        global-options-position = "before-subcommand";
        global-options =
          map
            (name: {
              names = [ name ];
              arity = "value";
            })
            [
              "-C"
              "-c"
              "--git-dir"
              "--work-tree"
              "--namespace"
              "--config-env"
              "--attr-source"
            ]
          ++ [
            {
              names = [ "--exec-path" ];
              arity = "optional-value";
            }
          ]
          ++
            map
              (name: {
                names = [ name ];
                arity = "flag";
              })
              [
                "-p"
                "-P"
                "--paginate"
                "--no-pager"
                "--bare"
                "--no-replace-objects"
                "--literal-pathspecs"
                "--glob-pathspecs"
                "--noglob-pathspecs"
                "--icase-pathspecs"
                "--no-optional-locks"
              ];
        rules = [
          # Agents publish through `jj git push`, which runs the Nix git
          # directly through `git.executable-path` and so bypasses this shim.
          {
            id = "git.push";
            kind = "refuse-subcommand";
            scope = [ "push" ];
            message = "Agents publish with `jj git push` instead.";
          }
        ];
      };
    };
  };

  # Shims reference the policy only through this derivation, so an invalid
  # policy fails the build instead of every agent command.
  validatedCommandPolicy =
    let
      unvalidated = pkgs.writeText "agent-command-policy-unvalidated.json" (
        builtins.toJSON commandPolicy
      );
    in
    pkgs.runCommandLocal "agent-command-policy.json" { } ''
      ${lib.getExe' agentPolicy "agent-policy"} validate ${unvalidated}
      cp ${unvalidated} "$out"
    '';

  # Builds the PATH shim for TOOL, which hands every invocation to
  # `agent-policy`; it runs the real binary or refuses with a corrective
  # message.
  mkPolicyShim =
    tool:
    pkgs.writeShellApplication {
      name = tool;
      text = ''
        exec ${lib.getExe' agentPolicy "agent-policy"} run --policy ${validatedCommandPolicy} ${tool} -- "$@"
      '';
    };

  jjShim = mkPolicyShim "jj";

  gitShim = mkPolicyShim "git";

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
