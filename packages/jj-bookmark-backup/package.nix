{
  jujutsu,
  pkgs,
}:
pkgs.python3Packages.buildPythonApplication {
  pname = "jj-bookmark-backup";
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
    installShellCompletion --cmd jj-bookmark-backup \
      --fish jj-bookmark-backup.fish \
      --zsh _jj-bookmark-backup
  '';

  postFixup = ''
    wrapProgram "$out/bin/jj-bookmark-backup" \
      --prefix PATH : ${pkgs.lib.makeBinPath [ jujutsu ]}
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    python3 -B -m unittest discover -s tests -p 'test_*.py'
    python3 -B -m unittest discover -s tests -p 'completion_test.py'
    "$out/bin/jj-bookmark-backup" --help >/dev/null
    runHook postInstallCheck
  '';
}
