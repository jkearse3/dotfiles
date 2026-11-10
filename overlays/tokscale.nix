final: prev:
let
  inherit (final.lib) any assertMsg;
  inherit (prev.tokscale) version;
  upstreamHasZstd = any (input: (input.pname or null) == final.zstd.pname) prev.tokscale.buildInputs;
in
{
  # Workaround for a tokscale 4.0.4 test that fails in checkPhase once its
  # fixture date has passed:
  #
  #   crates/tokscale-cli/src/tui/ui/usage.rs
  #     usage_reset_button_renders_when_credit_available
  #
  # The test fixture sets a reset credit to expire at a fixed
  # 2026-07-12T01:31:33Z and asserts the rendered text contains
  # "expires Jul 12". After that instant the UI correctly renders
  # "expires now", so the assertion fails regardless of the build machine.
  # Skipping only this test leaves the installed binary and every other test
  # unchanged.
  #
  # nixpkgs' cargo setup hook also exports ZSTD_SYS_USE_PKG_CONFIG=1, so
  # tokscale's zstd-sys dependency links the system libzstd it finds through
  # pkg-config instead of building its vendored copy. The package provides
  # pkg-config but not zstd, so the overlay adds zstd.
  #
  # Drop this overlay once the assertion below fires (i.e. nixpkgs moves off
  # 4.0.4 or adds zstd itself).
  tokscale =
    assert assertMsg (version == "4.0.4" && !upstreamHasZstd) (
      "Overlay overlays/tokscale.nix may no longer be needed: "
      + "tokscale=${version}, upstream has zstd=${final.lib.boolToString upstreamHasZstd}. "
      + "Try removing the overlay."
    );
    prev.tokscale.overrideAttrs (old: {
      checkFlags = (old.checkFlags or [ ]) ++ [
        "--skip=tui::ui::usage::tests::usage_reset_button_renders_when_credit_available"
      ];
      buildInputs = (old.buildInputs or [ ]) ++ [ final.zstd ];
    });
}
