{
  lib,
  pkgs,
  sqlit,
  ...
}:
{
  home = {
    packages = [ sqlit ];

    file.".config/sqlit/themes/tokyonight-night.json".source = ./themes/tokyonight-night.json;

    activation.sqlitSettings =
      lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
        ''
          settings="$HOME/.config/sqlit/settings.json"
          mkdir -p "$(dirname "$settings")"

          if [[ ! -f "$settings" ]]; then
            printf '{}\n' > "$settings"
          fi

          tmp="$(${pkgs.coreutils}/bin/mktemp)"
          ${pkgs.jq}/bin/jq -s '
            .[0] as $current |
            .[1] as $overlay |
            ($current * $overlay) |
            .custom_themes = ((($current.custom_themes // []) + ($overlay.custom_themes // [])) | unique)
          ' "$settings" ${./settings.json} > "$tmp"
          ${pkgs.coreutils}/bin/mv "$tmp" "$settings"
        '';
  };
}
