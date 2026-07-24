{ internalPkgs, ... }:
{
  programs.fish = {
    enable = true;
    interactiveShellInit = # fish
      ''
        source ${internalPkgs.git-worktree-cd.shellInit.fish}
      '';
  };

  # The `00-` prefix sorts ahead of `hm-session-vars.fish` in conf.d
  # alphabetical order, so brew runs first and HM's `home.sessionPath`
  # prepend (rendered into `hm-session-vars.fish` as a `set -gx PATH`
  # mutation of `$PATH`) lands on top of brew at the front of `$PATH`.
  # Result: user installs > brew > Nix > system.
  home.file.".config/fish/conf.d/00-brew.fish".text = # fish
    ''
      if test -e /opt/homebrew/bin/brew
          /opt/homebrew/bin/brew shellenv | source
      end

      if test -d /opt/homebrew/lib
          set -gx LIBRARY_PATH /opt/homebrew/lib $LIBRARY_PATH
      end
    '';
}
