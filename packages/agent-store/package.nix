{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "agent-store";
  version = "0-unstable";

  src = ./.;

  dontConfigure = true;
  dontBuild = true;

  # Git and jj are not wrapped in: the store must be resolved with the same VCS
  # tools the user runs against the repository.
  installPhase = ''
    runHook preInstall

    install -Dm755 agent-store.sh "$out/bin/agent-store"
    patchShebangs "$out/bin/agent-store"

    runHook postInstall
  '';

  meta = {
    description = "Locate and prepare a repository's ignored .agent state directories";
    license = pkgs.lib.licenses.mit;
    mainProgram = "agent-store";
  };
}
