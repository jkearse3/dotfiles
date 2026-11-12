# The `migrate-neovim-site` command the Neovim site migration activation step
# runs, built only after its fixture test passes against it.
{
  coreutils,
  lib,
  runCommandLocal,
  writeShellApplication,
}:
let
  migrate = writeShellApplication {
    name = "migrate-neovim-site";
    runtimeInputs = [ coreutils ];
    text = builtins.readFile ./migrate.sh;
  };
in
runCommandLocal "migrate-neovim-site-checked" { meta.mainProgram = "migrate-neovim-site"; } ''
  bash ${./migrate-test.sh} ${lib.getExe migrate}
  ln -s ${migrate} "$out"
''
