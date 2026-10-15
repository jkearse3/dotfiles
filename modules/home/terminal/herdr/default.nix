{
  dotfilesPackages,
  lib,
  mkSource,
  pkgs,
  ...
}:
let
  plugins = [
    dotfilesPackages.herdr-jj-workspaces
    dotfilesPackages.herdr-worktree-bootstrap
  ];

  completions = pkgs.runCommand "herdr-completions" { } ''
    mkdir -p $out/share/fish/vendor_completions.d $out/share/zsh/site-functions
    ${dotfilesPackages.herdr}/bin/herdr completion fish > $out/share/fish/vendor_completions.d/herdr.fish
    ${dotfilesPackages.herdr}/bin/herdr completion zsh > $out/share/zsh/site-functions/_herdr
  '';
  skill = pkgs.runCommand "herdr-skill" { } ''
    mkdir -p $out
    ${dotfilesPackages.herdr}/bin/herdr --skill > $out/SKILL.md
    test -s $out/SKILL.md
  '';
in
{
  imports = [
    ../../agents/registries.nix
    ../../lib/source.nix
  ];

  home = {
    packages = [
      dotfilesPackages.herdr
      completions
    ];
    file.".config/herdr/config.toml".source = mkSource ./config.toml;

    activation.herdrPlugins =
      lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
        ''
          herdr="${dotfilesPackages.herdr}/bin/herdr"
          jq="${pkgs.jq}/bin/jq"

          if ! current_plugins="$("$herdr" plugin list --json 2>/dev/null)" || ! printf '%s' "$current_plugins" | "$jq" -e '.result.plugins | type == "array"' > /dev/null; then
            echo "Herdr server is unavailable or returned malformed plugin data; skipping plugin reconciliation." >&2
          else
            while read -r plugin_id plugin; do
              if ! printf '%s' "$current_plugins" | "$jq" -e \
                --arg plugin_id "$plugin_id" \
                --arg plugin_path "$plugin" \
                'any(.result.plugins[]; .plugin_id == $plugin_id and .plugin_root == $plugin_path and .enabled == true)' > /dev/null; then
                if ! "$herdr" plugin link "$plugin" --enabled > /dev/null; then
                  echo "Failed to link and enable Herdr plugin $plugin_id." >&2
                  exit 1
                fi
              fi
            done <<'EOF'
          ${lib.concatMapStrings (plugin: "${plugin.pluginId} ${plugin}\n") plugins}EOF
          fi
        '';
  };
  agents.extraSkills = {
    herdr = skill;
  };
}
