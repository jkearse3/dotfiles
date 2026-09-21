{
  dotfilesPackages,
  ...
}:
{
  home.packages = [
    dotfilesPackages.jj-bookmark-nearest
    dotfilesPackages.jj-bookmark-current
    dotfilesPackages.jj-bookmark-default
    dotfilesPackages.jj-bookmark-stacked
    dotfilesPackages.jj-bookmark-previous
    dotfilesPackages.jj-bookmark-push
    dotfilesPackages.jj-bookmark-rebase
    dotfilesPackages.jj-bookmark-select
    dotfilesPackages.jj-change-select
    dotfilesPackages.jj-ensure
    dotfilesPackages.jj-bookmark-land
    dotfilesPackages.jj-description-format
    dotfilesPackages.jj-worktree-add
  ];

  programs = {
    jujutsu = {
      enable = true;
      settings = {
        ui = {
          diff-editor = ":builtin";
          paginate = "never";
          default-command = [
            "log"
            "--reversed"
          ];
        };
        revsets.bookmark-advance-to = "closest_pushable(@)";
        revset-aliases = {
          "closest_bookmark(to)" = "heads(::to & bookmarks())";
          "closest_pushable(to)" =
            ''heads(::to & mutable() & ~description(exact:"") & (~empty() | merges()))'';
          # Skips past the branch's own bookmark to find the base bookmark below
          # it (stacking-aware). Falls back to trunk() when no base bookmark exists.
          "branch(rev)" = "heads((::(closest_bookmark(rev-)-) & bookmarks()) | trunk())..rev";
          "branch()" = "branch(@)";
        };
      };
    };

    fish.shellAliases = {
      jjbl = "jj-bookmark-land";
      jjbp = "jj-bookmark-push";
      jjbr = "jj-bookmark-rebase";
    };
    zsh.shellAliases = {
      jjbl = "jj-bookmark-land";
      jjbp = "jj-bookmark-push";
      jjbr = "jj-bookmark-rebase";
    };
  };
}
