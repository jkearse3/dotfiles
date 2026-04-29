final: prev:
let
  inherit (final.lib) assertMsg boolToString;
  inherit (prev.direnv) version;
  doCheck = prev.direnv.doCheck or true;
in
{
  # Workaround for direnv 2.37.1 hanging in checkPhase on aarch64-darwin:
  # cache.nixos.org serves fish/zsh substitutes with broken code signatures,
  # which Gatekeeper kills when direnv's tests exec them. Drop this overlay
  # once the assertion below fires (i.e. nixpkgs moves off 2.37.1 or upstream
  # disables the check itself).
  # Tracking: https://github.com/NixOS/nixpkgs/issues/513019
  direnv =
    assert assertMsg (version == "2.37.1" && doCheck) (
      "Overlay modules/overlays/direnv.nix may no longer be needed: "
      + "direnv=${version}, doCheck=${boolToString doCheck}. "
      + "Try removing the overlay."
    );
    prev.direnv.overrideAttrs (_: {
      doCheck = false;
    });
}
