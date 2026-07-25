{
  internalPkgs,
  ...
}:
{
  home.packages = [
    internalPkgs.direnv-worktree
    internalPkgs.git-branch-checkout
    internalPkgs.git-branch-current
    internalPkgs.git-branch-default
    internalPkgs.git-branch-delete
    internalPkgs.git-branch-next
    internalPkgs.git-branch-previous
    internalPkgs.git-branch-stacked
    internalPkgs.git-worktree-cd
    internalPkgs.git-worktree-select
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
      hook.direnv-worktree = {
        command = "${internalPkgs.direnv-worktree}/bin/direnv-worktree post-checkout";
        event = "post-checkout";
      };
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
      "/.objectives/"
      ".nono/"
      ".playwright-cli/"
      ".jj"
      "**/.claude/settings.local.json"
    ];
  };
}
