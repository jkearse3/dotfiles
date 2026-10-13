{
  dotfilesPackages,
  ...
}:
{
  home.packages = [
    dotfilesPackages.direnv-worktree
    dotfilesPackages.worktree-include
  ];

  programs.git = {
    enable = true;
    settings = {
      core = {
        ignorecase = false;
        pager = "cat";
        editor = "vim";
      };
      init.defaultBranch = "main";
      # Git runs hooks in config order and Home Manager writes these sections
      # alphabetically, so this name must sort before direnv-worktree: a new
      # worktree's .envrc may source the local files this copies.
      hook.copy-worktree-includes = {
        command = "${dotfilesPackages.worktree-include}/bin/worktree-include --post-checkout";
        event = "post-checkout";
      };
      hook.direnv-worktree = {
        command = "${dotfilesPackages.direnv-worktree}/bin/direnv-worktree post-checkout";
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
