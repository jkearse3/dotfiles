{ pkgs }:

let
  package = pkgs.buildNpmPackage {
    pname = "playwright-cli";
    version = "0.1.18";

    src = pkgs.fetchFromGitHub {
      owner = "microsoft";
      repo = "playwright-cli";
      rev = "ca196c297169a494ee5517584883eada60dc8d0e";
      hash = "sha256-E/AzDJhD12PWSaA3iRY+hloPsSWnAw18gTa/ItVhr3E=";
    };

    npmDepsHash = "sha256-3kqiQvGtZfsmLHVWeCSM1yOYb+ws2x1vMPC1OuvrKAI=";
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
