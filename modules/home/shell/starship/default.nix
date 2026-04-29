{
  lib,
  pkgs,
  ...
}:
let
  jj-bookmark-nearest = pkgs.callPackage ../../vcs/jj/jj-bookmark-nearest/package.nix { };
  jj-starship-prompt = pkgs.writeShellApplication {
    name = "jj-starship-prompt";
    runtimeInputs = [
      pkgs.jujutsu
      jj-bookmark-nearest
    ];
    text = builtins.readFile ./jj-starship-prompt.sh;
  };
in
{
  home.packages = [
    jj-starship-prompt
  ];
  programs.starship = {
    enable = true;
    settings = {
      "$schema" = "https://starship.rs/config-schema.json";
      add_newline = true;
      command_timeout = 1000;
      format = lib.concatStrings [
        "$username$hostname$directory"
        "$git_branch$git_commit$git_state"
        "$git_status\${custom.jj}$cmd_duration"
        "$line_break"
        "$character"
        "$line_break"
      ];
      directory = {
        truncate_to_repo = false;
        truncation_length = 5;
      };
      cmd_duration = {
        format = "[$duration]($style) ";
        style = "yellow";
        show_milliseconds = true;
        min_time = 0;
      };
      custom.jj = {
        command = "jj-starship-prompt";
        when = "jj root 2>/dev/null";
        format = "$output ";
        unsafe_no_escape = true;
        description = "Combined jj status with per-segment ANSI colors";
      };
    };
  };
}
