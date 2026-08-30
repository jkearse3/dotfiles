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

  jjShim = pkgs.writeShellApplication {
    name = "jj";
    text = ''
      exec ${lib.getExe pkgs.jujutsu} \
        --config ${lib.escapeShellArg "ui.diff-editor=${
          builtins.toJSON [
            denied
            "jj"
            "diff-editor"
          ]
        }"} \
        --config ${lib.escapeShellArg "ui.merge-editor=${
          builtins.toJSON [
            denied
            "jj"
            "merge-editor"
          ]
        }"} \
        "$@"
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
          ${lib.getExe' pkgs.openssh "ssh-keygen"}
        touch "$out"
      '';
in
{
  inherit
    check
    environment
    jjShim
    shellExports
    ;
}
