{
  herdr,
  pkgs,
}:
pkgs.python3Packages.buildPythonApplication {
  pname = "herdr-find";
  version = "0.0.0";
  pyproject = true;

  src = ./.;
  build-system = [ pkgs.python3Packages.setuptools ];
  nativeBuildInputs = [ pkgs.makeWrapper ];

  postFixup = ''
    wrapProgram "$out/bin/herdr-find" --prefix PATH : "${pkgs.lib.makeBinPath [ herdr ]}"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HERDR_FIND="$out/bin/herdr-find" \
      python3 -B -m unittest discover -s tests -p 'test_*.py'
    "$out/bin/herdr-find" rows --help > /dev/null
    "$out/bin/herdr-find" preview --help > /dev/null
    runHook postInstallCheck
  '';
}
