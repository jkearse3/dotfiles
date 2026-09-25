final: prev:
let
  inherit (final.lib) assertMsg boolToString;
  inherit (prev.secretspec) version;
  doCheck = prev.secretspec.doCheck or true;
in
{
  # Workaround for two secretspec 0.21.0 tests failing in checkPhase when the
  # build directory path is long, as with Nix >= 2.30's default build-dir
  # (/nix/var/nix/builds/nix-<pid>-<random>) on Darwin:
  #
  #   tests/claude_integration.rs configure_refuses_to_replace_an_unmanaged_helper
  #   tests/claude_integration.rs unconfigure_refuses_to_remove_an_edited_managed_helper
  #
  # secretspec behaves correctly in both tests. They fail only because they
  # match stderr against phrases ("managed by SecretSpec", "outside
  # SecretSpec") that follow a fixture path under $TMPDIR. miette's graphical
  # handler wraps errors at 80 columns when stderr is not a terminal, so a
  # long enough path pushes a line break into the phrase ("not managed\n  │ by
  # SecretSpec"). Linux sandbox builds use TMPDIR=/build, which is too short to
  # trigger the wrap.
  #
  # NO_GRAPHICS=1 selects miette's narratable handler, which never wraps. It
  # reaches the binary under test because the tests do not clear the
  # environment. This only changes how errors are formatted during the check;
  # the installed binary is unaffected, and every test still runs. Drop this
  # overlay once the assertion below fires (i.e. nixpkgs moves off 0.21.0 or
  # disables the check itself).
  secretspec =
    assert assertMsg (version == "0.21.0" && doCheck) (
      "Overlay flake/overlays/secretspec.nix may no longer be needed: "
      + "secretspec=${version}, doCheck=${boolToString doCheck}. "
      + "Try removing the overlay."
    );
    prev.secretspec.overrideAttrs (old: {
      preCheck = (old.preCheck or "") + ''
        export NO_GRAPHICS=1
      '';
    });
}
