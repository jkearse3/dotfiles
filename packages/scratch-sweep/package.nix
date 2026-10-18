{
  pkgs,
}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "scratch-sweep";
  version = "0-unstable";

  src = ./.;

  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.python3
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 scratch_sweep.py "$out/bin/scratch-sweep"
    patchShebangs "$out/bin/scratch-sweep"
    # `lsof` is pinned because the script parses its output format and macOS
    # ships a different build. `ps` is the system one, which prints the
    # path each process was executed with on macOS.
    wrapProgram "$out/bin/scratch-sweep" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.lsof
        ]
      }

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    python3 -B scratch_sweep_test.py
    "$out/bin/scratch-sweep" --help >/dev/null

    runHook postInstallCheck
  '';
}
