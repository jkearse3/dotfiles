{
  commit-message,
  jujutsu,
  pkgs,
}:
pkgs.python3Packages.buildPythonApplication {
  pname = "jj-description-format";
  version = "0.0.0";
  pyproject = true;

  src = ./.;
  build-system = [ pkgs.python3Packages.setuptools ];
  nativeBuildInputs = [
    pkgs.installShellFiles
    pkgs.makeWrapper
  ];
  nativeCheckInputs = [
    commit-message
    pkgs.fish
    pkgs.git
    jujutsu
    pkgs.zsh
  ];

  postInstall = ''
    installShellCompletion --cmd jj-description-format \
      --fish jj-description-format.fish \
      --zsh _jj-description-format
  '';

  postFixup = ''
    wrapProgram "$out/bin/jj-description-format" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          commit-message
          jujutsu
        ]
      }
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    python3 -B -m unittest discover -s tests -p 'test_*.py'
    python3 -B -m unittest discover -s tests -p 'completion_test.py'
    "$out/bin/jj-description-format" --help >/dev/null
    runHook postInstallCheck
  '';
}
