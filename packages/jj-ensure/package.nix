{
  jujutsu,
  pkgs,
}:
pkgs.python3Packages.buildPythonApplication {
  pname = "jj-ensure";
  version = "0.0.0";
  pyproject = true;

  src = ./.;

  build-system = [
    pkgs.python3Packages.setuptools
  ];

  nativeBuildInputs = [
    pkgs.installShellFiles
    pkgs.makeWrapper
  ];

  nativeCheckInputs = [
    pkgs.fish
    pkgs.git
    jujutsu
    pkgs.zsh
  ];

  postInstall = ''
    installShellCompletion --cmd jj-ensure \
      --fish jj-ensure.fish \
      --zsh _jj-ensure
  '';

  postFixup = ''
    wrapProgram "$out/bin/jj-ensure" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.git
          jujutsu
        ]
      }
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    python3 -B -m unittest discover -s tests -p 'test_*.py'
    python3 -B -m unittest discover -s tests -p 'completion_test.py'
    "$out/bin/jj-ensure" --help >/dev/null
    runHook postInstallCheck
  '';
}
