{ pkgs }:

let
  package = pkgs.buildNpmPackage {
    pname = "playwright-cli";
    version = "0.1.25";

    src = pkgs.fetchFromGitHub {
      owner = "microsoft";
      repo = "playwright-cli";
      rev = "c872a33cec77fa03c28fa7c6d1ad99d15d04ce42";
      hash = "sha256-WCtATa/1WKl7XJxvgrbgslKdH0vh4Bf/p6VX3nGC9rQ=";
    };

    npmDepsHash = "sha256-sewzAMYMgoJTIwK/Jlejhlxh3dyozlAzfD2czioCWAo=";
    dontNpmBuild = true;

    meta = {
      description = "Agent-oriented Playwright CLI";
      homepage = "https://github.com/microsoft/playwright-cli";
      license = pkgs.lib.licenses.asl20;
      mainProgram = "playwright-cli";
    };
  };
in
pkgs.symlinkJoin {
  name = "playwright-cli-${package.version}";
  inherit (package) version;
  paths = [ package ];
  buildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/playwright-cli \
      --set PLAYWRIGHT_BROWSERS_PATH ${pkgs.playwright-driver.browsers} \
      --set PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS true \
      --run 'export PLAYWRIGHT_DAEMON_SOCKETS_DIR="/tmp/playwright-cli-''${USER:-user}"'
  '';
  inherit (package) meta;
  passthru.updateScript = ./update.sh;
}
