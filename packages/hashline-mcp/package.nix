{ pkgs }:
pkgs.python3Packages.buildPythonApplication {
  pname = "hashline-mcp";
  version = "0.1.0";
  pyproject = true;
  src = ./.;
  build-system = [ pkgs.python3Packages.setuptools ];
  pythonImportsCheck = [ "hashline_mcp" ];

  # `grep` shells out to ripgrep, so pin it rather than trusting the session PATH.
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (pkgs.lib.makeBinPath [ pkgs.ripgrep ])
  ];
  nativeInstallCheckInputs = [ pkgs.ripgrep ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export PYTHONPATH="$out/${pkgs.python3.sitePackages}"
    python3 -B -m unittest discover -s tests -p 'test_*.py'
    python3 -B tests/check_installed.py "$out"
    runHook postInstallCheck
  '';

  meta = {
    description = "Anchored line editing for coding agents over MCP";
    mainProgram = "hashline-mcp";
  };
}
