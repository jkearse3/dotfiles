# The Herdr runtime `herdr-core` (CLI `hc`) from llm-agents, wrapped so a core
# it starts never inherits the Herdr TUI's pane variables. The TUI sets these
# six in every pane (herdr 0.9.5 `src/pane.rs`, `src/integration/env.rs`
# `apply_pane_base_env`); a core first started from a TUI pane would pass them
# to every app terminal, where the TUI's pi integration and TUI-or-app
# detection would act on them. `HC_SOCKET` is left alone.
{
  lib,
  makeWrapper,
  stdenvNoCC,
  upstream,
}:
let
  tuiPaneVariables = [
    "HERDR_ENV"
    "HERDR_PANE_ID"
    "HERDR_SOCKET_PATH"
    "HERDR_TAB_ID"
    "HERDR_WORKSPACE_ID"
    "HERDR_BIN_PATH"
  ];
  unsetFlags = lib.concatMapStringsSep " " (name: "--unset ${name}") tuiPaneVariables;
  executables = [
    "herdr-core"
    "hc"
  ];
in
stdenvNoCC.mkDerivation {
  pname = "herdr-core";
  inherit (upstream) version;

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    for name in ${lib.concatStringsSep " " executables}; do
      makeWrapper ${upstream}/bin/herdr-core "$out/bin/$name" ${unsetFlags}
    done
    ln -s ${upstream}/share "$out/share"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    for name in ${lib.concatStringsSep " " executables}; do
      wrapper="$out/bin/$name"
      grep -qF 'exec "${upstream}/bin/herdr-core"' "$wrapper"
      for variable in ${lib.concatStringsSep " " tuiPaneVariables}; do
        grep -qxF "unset $variable" "$wrapper"
      done
    done
    test "$("$out/bin/hc" --version)" = "hc ${upstream.version}"
    test -s "$out/share/skills/herdr-core/herdr-core/SKILL.md"
    runHook postInstallCheck
  '';

  inherit (upstream) meta;
}
