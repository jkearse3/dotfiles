{ pkgs }:

let
  package = pkgs.buildNpmPackage {
    pname = "playwright-cli";
    version = "0.1.15";

    src = pkgs.fetchFromGitHub {
      owner = "microsoft";
      repo = "playwright-cli";
      rev = "74d9bf144a96770b6295ceedecb07a2fd7e86775";
      hash = "sha256-M0NZ7h1kSIsxktMWe5n75LDc+MHZvSq6b+iRx6opakU=";
    };

    npmDepsHash = "sha256-ZrO8yIqMYMQUlsQraejVgKRZ7klC5/8UsV3/H1EqYtA=";
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
  paths = [ package ];
  buildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/playwright-cli \
      --set PLAYWRIGHT_BROWSERS_PATH ${pkgs.playwright-driver.browsers} \
      --set PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS true \
      --run 'export PLAYWRIGHT_DAEMON_SOCKETS_DIR="/tmp/playwright-cli-''${USER:-user}"'
  '';
  meta = package.meta;
}
