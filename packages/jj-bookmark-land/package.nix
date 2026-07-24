{
  jujutsu,
  pkgs,
}:
pkgs.python3Packages.buildPythonApplication {
  pname = "jj-bookmark-land";
  version = "0.0.0";
  pyproject = true;

  src = ./.;
  build-system = [ pkgs.python3Packages.setuptools ];
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
    installShellCompletion --cmd jj-bookmark-land \
      --fish jj-bookmark-land.fish \
      --zsh _jj-bookmark-land
  '';

  postFixup = ''
    wrapProgram "$out/bin/jj-bookmark-land" \
      --prefix PATH : ${pkgs.lib.makeBinPath [ jujutsu ]}
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    python3 -B -m unittest discover -s tests -p 'test_*.py'
    python3 -B -m unittest discover -s tests -p 'completion_test.py'
    "$out/bin/jj-bookmark-land" --help >/dev/null
    runHook postInstallCheck
  '';
}
