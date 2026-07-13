{
  commit-message-check,
  pkgs,
}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "commit-message-format";
  version = "0-unstable";

  src = ./.;

  nativeBuildInputs = [
    pkgs.python3
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 commit-message-format.py "$out/bin/commit-message-format"
    patchShebangs "$out/bin/commit-message-format"

    runHook postInstall
  '';

  doInstallCheck = true;

  installCheckPhase = ''
    runHook preInstallCheck

    FORMATTER="$out/bin/commit-message-format" \
      CHECKER="${commit-message-check}/bin/commit-message-check" \
      python3 test-commit-message-format.py

    runHook postInstallCheck
  '';
}
