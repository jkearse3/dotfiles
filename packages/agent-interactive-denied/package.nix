{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "agent-interactive-denied";
  version = "0-unstable";

  src = ./.;

  nativeBuildInputs = [ pkgs.bash ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 agent-interactive-denied.sh "$out/bin/agent-interactive-denied"
    patchShebangs "$out/bin/agent-interactive-denied"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    ${pkgs.bash}/bin/bash "$src/test.sh" "$out/bin/agent-interactive-denied"

    runHook postInstallCheck
  '';

  meta = {
    description = "Fail fast when coding agents invoke interactive VCS helpers";
    license = pkgs.lib.licenses.mit;
    mainProgram = "agent-interactive-denied";
  };
}
