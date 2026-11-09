# The `herdr-space-new` command the `space-new` mod runs in a popup
# terminal: the fixture-checked folder picker with its real tools.
{
  herdrApp,
  pkgs,
}:
let
  # The folder picker the `space-new` mod runs in a popup terminal. It takes
  # its tools as arguments so the fixtures can pass fakes; `spaceNew` passes
  # the real ones. GNU grep drops the folder offered first from `fd`'s list.
  spaceNewPicker = pkgs.writeShellApplication {
    name = "herdr-space-new-picker";
    runtimeInputs = [ pkgs.gnugrep ];
    text = builtins.readFile ./space-new.sh;
  };

  # The `space-new` mod runs the picker through this path, so failing
  # fixtures fail the build.
  checkedSpaceNewPicker = pkgs.runCommandLocal "herdr-space-new-picker-checked" { } ''
    bash ${./space-new-test.sh} ${spaceNewPicker}/bin/herdr-space-new-picker ${pkgs.fd}/bin/fd
    ln -s ${spaceNewPicker} "$out"
  '';

  # Takes the picker's remaining arguments: the folder offered first.
  spaceNew = pkgs.writeShellScript "herdr-space-new" ''
    exec ${checkedSpaceNewPicker}/bin/herdr-space-new-picker ${pkgs.fd}/bin/fd ${pkgs.fzf}/bin/fzf ${herdrApp}/bin/herdr-app "$@"
  '';
in
spaceNew
