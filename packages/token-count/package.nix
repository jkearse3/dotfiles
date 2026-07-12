{ pkgs }:

let
  python = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.tiktoken ]);
  encodingData = pkgs.fetchurl {
    url = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken";
    hash = "sha256-RGqVOMtsNI41FhINfAiwn1fDZJXirP/+WaW/iwz7Gi0=";
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "token-count";
  version = "0-unstable";

  src = ./.;

  nativeBuildInputs = [
    pkgs.makeWrapper
    python
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 token-count.py "$out/bin/token-count"
    install -Dm644 ${encodingData} \
      "$out/share/token-count/tiktoken/fb374d419588a4632f3f557e76b4b70aebbca790"
    patchShebangs "$out/bin/token-count"
    wrapProgram "$out/bin/token-count" \
      --set TIKTOKEN_CACHE_DIR "$out/share/token-count/tiktoken"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    for test_case in stdin-equivalence multiple-inputs json-output error-cases; do
      ${pkgs.bash}/bin/bash "$src/test.sh" "$out/bin/token-count" "$test_case"
    done
    "$out/bin/token-count" --help | grep -Fq o200k_base

    runHook postInstallCheck
  '';

  meta = {
    description = "Count o200k_base reference tokens in text inputs";
    license = pkgs.lib.licenses.mit;
    mainProgram = "token-count";
  };
}
