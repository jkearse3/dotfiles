final: prev:
let
  inherit (final.lib) assertMsg;
  inherit (prev.nix-output-monitor) version;
in
{
  # Workaround for nom 2.2.0 rejecting internal-json messages whose activity or
  # result type it does not know. Determinate Nix 3.23 emits OpenTelemetry
  # activities (type 10113), so every build through `nom` prints:
  #
  #   ParseNixJSONMessageError ... "invalid activity type: 10113"
  #
  # The patch maps unknown types to nom's existing Unknown handling instead of
  # failing. It is vendored from upstream PR #321 so the build does not depend
  # on an unmerged PR branch staying fetchable.
  #   https://github.com/maralorn/nix-output-monitor/issues/320
  #   https://github.com/maralorn/nix-output-monitor/pull/321
  # Drop this overlay once the assertion below fires (i.e. nixpkgs moves off
  # 2.2.0) and the new release includes the fix.
  nix-output-monitor =
    assert assertMsg (version == "2.2.0") (
      "Overlay overlays/nix-output-monitor.nix may no longer be needed: "
      + "nix-output-monitor=${version}. Try removing the overlay."
    );
    prev.nix-output-monitor.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./nix-output-monitor-unknown-message-types.patch ];
    });
}
