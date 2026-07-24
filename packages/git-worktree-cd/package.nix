{
  pkgs,
}:
pkgs.runCommand "git-worktree-cd"
  {
    passthru.shellInit = {
      bash = ./git-worktree-cd.bash;
      fish = ./git-worktree-cd.fish;
      zsh = ./git-worktree-cd.zsh;
    };
  }
  ''
    install -Dm644 ${./git-worktree-cd.bash} $out/share/git-worktree-cd/git-worktree-cd.bash
    install -Dm644 ${./git-worktree-cd.zsh} $out/share/git-worktree-cd/git-worktree-cd.zsh
    install -Dm644 ${./git-worktree-cd.fish} $out/share/git-worktree-cd/git-worktree-cd.fish
  ''
