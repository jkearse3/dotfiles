{
  ...
}:
{
  imports = [
    ./git-branch-checkout
    ./git-branch-current
    ./git-branch-default
    ./git-branch-delete
    ./git-branch-next
    ./git-branch-previous
    ./git-branch-stacked
  ];
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Johnnie Kearse III";
        email = "jkearse3@gmail.com";
      };
      core = {
        ignorecase = false;
        pager = "cat";
        editor = "vim";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
      url."git@github.com:".insteadOf = "https://github.com/";
      alias = {
        a = "add";
        aA = "add -A";
        co = "checkout";
        cob = "checkout -b";
        b = "branch";
        ba = "branch -a";
        bd = "branch -d";
        bD = "branch -D";
        cm = "commit -m";
        cam = "commit --amend -m";
        caa = "commit -a --amend -C HEAD";
        d = "diff";
        fop = "fetch origin --prune";
        ls = ''log --pretty=format:"%C(yellow)%h%Cred%d %Creset%s%Cblue [%cn]" --decorate'';
        ll = ''log --pretty=format:"%C(yellow)%h%Cred%d %Creset%s%Cblue [%cn]" --decorate --numstat'';
        mg = "merge";
        pl = "pull";
        plo = "pull origin";
        puo = "push origin";
        rao = "remote add origin";
        rgu = "remote get-url";
        rguo = "remote get-url origin";
        rsu = "remote set-url";
        rsuo = "remote set-url origin";
        st = "status";
        ucs = "reset --soft HEAD^";
        ucm = "reset --mixed HEAD^";
      };
    };
    ignores = [
      "*.local"
      "*.local.*"
      ".DS_Store"
      ".claude/_*/"
      ".jj"
      "**/.claude/settings.local.json"
    ];
  };
}
