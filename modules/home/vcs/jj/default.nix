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
        aliases.x = [
          "util"
          "exec"
          "--"
          "jjx"
        ];
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
