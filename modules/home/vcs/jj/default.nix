{
  dotfilesPackages,
  ...
}:
{
  home.packages = [
    dotfilesPackages.jjx
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
        aliases = {
          x = [
            "util"
            "exec"
            "--"
            "jjx"
          ];
          ss = [
            "show"
            "--stat"
          ];
          bs = [
            "log"
            "--stat"
            "--reversed"
            "-r"
            "branch()"
          ];
        };
        git.private-commits = ''bookmarks(glob:"backup-*")'';
        revsets.bookmark-advance-to = "closest_pushable(@)";
        revset-aliases = {
          "closest_bookmark(to)" = "heads(::to & bookmarks())";
          "closest_pushable(to)" =
            ''heads(::to & mutable() & ~description(exact:"") & (~empty() | merges()))'';
          # Skips past the branch's own bookmark to find the base bookmark below
          # it (stacking-aware). Falls back to trunk() when no base bookmark exists.
          "branch(rev)" = "heads((::(closest_bookmark(rev-)-) & bookmarks()) | trunk())..rev";
          "branch()" = "branch(@)";
          # jj's default trunk() without its root() fallback, then a local
          # main, master, or trunk bookmark for repositories without a remote.
          # Cloned repositories set their own trunk() and are unaffected.
          "trunk()" = ''
            coalesce(
              latest(
                remote_bookmarks(exact:"main", exact:"origin") |
                remote_bookmarks(exact:"master", exact:"origin") |
                remote_bookmarks(exact:"trunk", exact:"origin") |
                remote_bookmarks(exact:"main", exact:"upstream") |
                remote_bookmarks(exact:"master", exact:"upstream") |
                remote_bookmarks(exact:"trunk", exact:"upstream")
              ),
              latest(bookmarks(exact:"main") | bookmarks(exact:"master") | bookmarks(exact:"trunk")),
              root()
            )
          '';
        };
      };
    };

    fish.shellAliases = {
      jjbb = "jjx bookmark backup";
      jjbp = "jjx bookmark push";
      jjbr = "jjx bookmark rebase";
      jjbs = "jjx bookmark sweep";
    };
    zsh.shellAliases = {
      jjbb = "jjx bookmark backup";
      jjbp = "jjx bookmark push";
      jjbr = "jjx bookmark rebase";
      jjbs = "jjx bookmark sweep";
    };
  };
}
