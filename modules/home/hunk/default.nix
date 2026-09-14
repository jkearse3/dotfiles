{
  dotfilesPackages,
  lib,
  pkgs,
  ...
}:
let
  hunkConfigPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.tomlkit ]);
  hunkConfigMerge = pkgs.writeShellApplication {
    name = "hunk-config-merge";
    text = ''
      exec ${hunkConfigPython}/bin/python ${./hunk-config-merge.py} "$@"
    '';
  };

  hunkConfigMergeChecked = pkgs.runCommandLocal "hunk-config-merge-checked" { } ''
    ${pkgs.bash}/bin/bash ${./hunk-config-merge-test.sh} ${hunkConfigMerge}/bin/hunk-config-merge
    ln -s ${hunkConfigMerge} $out
  '';
in
{
  imports = [ ../agents/registries.nix ];

  home = {
    packages = [ dotfilesPackages.hunk ];

    # Hunk rewrites this file when the user saves view preferences. Keep the
    # live file writable and merge tracked values only as missing defaults.
    activation.hunkConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${hunkConfigMergeChecked}/bin/hunk-config-merge \
        "$HOME/.config/hunk/config.toml" \
        ${./config.toml}
    '';
  };

  agents.extraSkills."hunk-review" = "${dotfilesPackages.hunk.outPath}/skills/hunk-review";
}
