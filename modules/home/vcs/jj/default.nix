{
  internalPkgs,
  ...
}:
{
  home.packages = [
    internalPkgs.jj-bookmark-nearest
    internalPkgs.jj-bookmark-current
    internalPkgs.jj-bookmark-default
    internalPkgs.jj-bookmark-stacked
    internalPkgs.jj-bookmark-previous
    internalPkgs.jj-bookmark-select
    internalPkgs.jj-change-select
    internalPkgs.jj-ensure
    internalPkgs.jj-worktree-add
  ];

  programs.jujutsu = {
    enable = true;
    settings = {
      user = {
        name = "Johnnie Kearse III";
        email = "jkearse3@gmail.com";
      };
      ui = {
        diff-editor = ":builtin";
        paginate = "never";
        default-command = [
          "log"
          "--reversed"
        ];
      };
      revset-aliases = {
        "closest_bookmark(to)" = "heads(::to & bookmarks())";
        "closest_pushable(to)" =
          ''heads(::to & mutable() & ~description(exact:"") & (~empty() | merges()))'';
        # Skips past the branch's own bookmark to find the base bookmark below
        # it (stacking-aware). Falls back to trunk() when no base bookmark exists.
        "branch(rev)" = "heads((::(closest_bookmark(rev-)-) & bookmarks()) | trunk())..rev";
        "branch()" = "branch(@)";
        "focus" = "fork_point(@ | trunk())::heads(@::) | trunk()";
        "clean" = "@ | ancestors(@, 30) & merges() | trunk()";
      };
      aliases = {
        tug = [
          "bookmark"
          "move"
          "--from"
          "closest_bookmark(@)"
          "--to"
          "closest_pushable(@)"
        ];
        ll = [
          "log"
          "--reversed"
          "-s"
        ];
        stat = [
          "show"
          "--stat"
        ];
        divergent = [
          "log"
          "-r"
          "divergent()"
          "--no-graph"
          "-T"
          ''change_id.shortest() ++ " -> " ++ commit_id.short() ++ " (" ++ format_timestamp(committer.timestamp()) ++ ")\n"''
        ];
      };
    };
  };
}
