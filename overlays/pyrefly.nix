final: prev:
let
  inherit (final.lib)
    any
    assertMsg
    boolToString
    hasInfix
    ;
  inherit (prev.pyrefly) version;
  cargoSetupHook = "${prev.path}/pkgs/build-support/rust/hooks/cargo-setup-hook.sh";
  hookForcesZstdPkgConfig = hasInfix ''export ZSTD_SYS_USE_PKG_CONFIG="1"'' (
    builtins.readFile cargoSetupHook
  );
  upstreamHasPkgConfig = any (
    input: (input.pname or null) == final.pkg-config.pname
  ) prev.pyrefly.nativeBuildInputs;
in
{
  # Workaround for a pyrefly 1.3.2 build failure in zstd-sys's build script:
  #
  #   The pkg-config command could not be found.
  #
  # nixpkgs' cargo setup hook exports ZSTD_SYS_USE_PKG_CONFIG=1, which makes
  # zstd-sys (a pyrefly dependency) link the system libzstd found through
  # pkg-config instead of building its vendored copy. The pyrefly package
  # provides neither pkg-config nor zstd, so the probe panics. Adding both lets
  # zstd-sys find libzstd. Drop this overlay once the assertion below fires
  # (i.e. pyrefly moves off 1.3.2, the hook stops forcing pkg-config, or
  # upstream adds pkg-config itself).
  pyrefly =
    assert assertMsg (version == "1.3.2" && hookForcesZstdPkgConfig && !upstreamHasPkgConfig) (
      "Overlay overlays/pyrefly.nix may no longer be needed: "
      + "pyrefly=${version}, "
      + "cargo setup hook forces zstd pkg-config=${boolToString hookForcesZstdPkgConfig}, "
      + "upstream has pkg-config=${boolToString upstreamHasPkgConfig}. "
      + "Try removing the overlay."
    );
    prev.pyrefly.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.pkg-config ];
      buildInputs = (old.buildInputs or [ ]) ++ [ final.zstd ];
    });
}
