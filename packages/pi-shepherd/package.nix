{ herdr, pkgs }:
pkgs.python3Packages.buildPythonApplication {
  pname = "pi-shepherd";
  version = "0.1.0";
  pyproject = true;
  src = ./.;
  build-system = [ pkgs.python3Packages.setuptools ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  pythonImportsCheck = [ "pi_shepherd" ];

  postInstall = ''
    mkdir -p $out/share/pi-shepherd
    cp src/pi_shepherd/SKILL.md $out/share/pi-shepherd/SKILL.md
  '';
  postFixup = ''
    wrapProgram "$out/bin/pi-shepherd" --prefix PATH : ${pkgs.lib.makeBinPath [ herdr ]}
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export PYTHONPATH="$out/${pkgs.python3.sitePackages}"
    export PATH="${pkgs.lib.makeBinPath [ herdr ]}:$PATH"
    python3 -B -m unittest discover -s tests -p 'test_*.py'
    python3 -B tests/check_installed.py "$out"
    runHook postInstallCheck
  '';
}
