{
  jujutsu,
  pkgs,
}:
pkgs.writeShellApplication {
  name = "jj-bookmark-rebase";
  runtimeInputs = [
    jujutsu
    pkgs.fzf
  ];
  text = builtins.readFile ./jj-bookmark-rebase.sh;

  derivationArgs.nativeBuildInputs = [
    pkgs.bash
    pkgs.git
    jujutsu
  ];
  checkPhase = ''
    runHook preCheck
    ${pkgs.stdenv.shellDryRun} "$target"
    ${pkgs.lib.getExe pkgs.shellcheck-minimal} "$target"
    ${pkgs.bash}/bin/bash ${./test.sh} "$target"
    runHook postCheck
  '';
}
