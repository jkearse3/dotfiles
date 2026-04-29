{
  lib,
  config,
  ...
}:
{
  programs.zsh = {
    enable = true;

    dotDir = "${config.xdg.configHome}/zsh";

    autocd = true;

    history = {
      append = true;
    };

    setOptions = [
      "AUTO_PUSHD"
      "PUSHD_IGNORE_DUPS"
      "PUSHD_SILENT"
      "COMPLETE_IN_WORD"
      "ALWAYS_TO_END"
      "HIST_REDUCE_BLANKS"
      "INC_APPEND_HISTORY"
    ];

    # Override the default `autoload -U compinit && compinit` to land the
    # customized `zstyle`/`zmodload`/`_comp_options` lines at mkOrder 570
    # alongside compinit. Avoids a duplicate compinit later in the file.
    completionInit = # zsh
      ''
        autoload -U compinit && compinit
        zstyle ':completion:*' menu select
        zmodload zsh/complist
        _comp_options+=(globdots)
      '';

    # `lib.mkBefore` resolves to mkOrder 500, ahead of HM's order-510
    # `typeset -U path cdpath fpath manpath` and ahead of every PATH write
    # in the rendered `~/.zshrc`. Must precede any PATH write so inherited
    # PATH (tmux panes, child shells) can't accumulate duplicates.
    initContent = lib.mkBefore "typeset -U path PATH\n";
  };

  # Brew shellenv lands in `~/.zshenv` ahead of HM's stub `source` line
  # via `lib.mkBefore`, so brew prepends to `$PATH` first. The stub then
  # sources `${dotDir}/.zshenv`, which loads `hm-session-vars.sh` and
  # `home.sessionPath` on top. Result: user installs > brew > Nix >
  # system.
  #
  # With `programs.zsh.dotDir` set to an XDG path, HM writes a stub at
  # `~/.zshenv` keyed `home.file.".zshenv"` that sources the real config
  # under `dotDir`. Same key required to merge.
  home.file.".zshenv".text =
    lib.mkBefore # zsh
      ''
        eval "$(/opt/homebrew/bin/brew shellenv)"

        if [[ -d /opt/homebrew/lib ]]; then
            export LIBRARY_PATH="/opt/homebrew/lib:$LIBRARY_PATH"
        fi
      '';
}
