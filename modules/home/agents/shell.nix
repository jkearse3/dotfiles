# The shell every agent frontend runs model-issued commands in, and the shared
# rule that tells agents what that environment provides. Frontends otherwise
# pick a shell on their own — Claude Code and OpenCode fall back to zsh when the
# login shell is fish, and pi hardcodes `/bin/bash`, which is bash 3.2 on
# macOS — so one session's commands can fail in another.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # The GNU tools the rule promises. The home profile installs them from
  # `modules/home/shell`; the assertion below keeps the two lists agreeing.
  gnuTools = [
    {
      package = pkgs.coreutils;
      commands = "coreutils";
    }
    {
      package = pkgs.gnused;
      commands = "sed";
    }
    {
      package = pkgs.gawk;
      commands = "awk (gawk)";
    }
    {
      package = pkgs.gnugrep;
      commands = "grep";
    }
    {
      package = pkgs.findutils;
      commands = "find, xargs";
    }
  ];
  missingGnuTools = lib.filter (tool: !(lib.elem tool.package config.home.packages)) gnuTools;

  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  gnuToolList = lib.concatMapStringsSep "\n" (
    tool: "- ${tool.commands} ${tool.package.version}"
  ) gnuTools;

  # Versions come from the packages the generation installs, so the rule
  # changes with them. `builtins.toFile` keeps the text out of a derivation,
  # which lets the stitched instruction files read it at eval time.
  shellEnvironmentRule = builtins.toFile "shell-environment.md" ''
    # Shell Environment

    Shell commands run non-interactively in GNU bash ${pkgs.bashInteractive.version}
    (`${config.agents.shellPath}`), whatever the user's login or terminal shell
    is. Write bash, not fish or zsh syntax.

    The Nix home profile puts these GNU tools on PATH:

    ${gnuToolList}

    Use GNU flags such as `sed -i`, `stat -c`, and `date -d`. When a flag's
    availability matters, check `<tool> --version` first.
    ${lib.optionalString isDarwin ''

      On macOS these shadow the BSD versions in `/usr/bin`, so BSD forms such as
      `sed -i '''`, `stat -f`, and `date -j` fail. `tar` remains BSD tar.
    ''}'';
in
{
  options.agents.shellPath = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "${config.home.profileDirectory}/bin/bash";
    description = ''
      Absolute path of the bash that agent frontends run shell commands in.

      It points into the home profile rather than the Nix store so frontends
      that persist it in their own mutable settings, such as pi, keep a path
      that survives garbage collection across generations.
    '';
  };

  config = {
    assertions = [
      {
        assertion = missingGnuTools == [ ];
        message = "the shell-environment agent rule lists GNU tools the home profile does not install: ${
          lib.concatMapStringsSep ", " (tool: tool.package.pname) missingGnuTools
        }";
      }
    ];

    home.packages = [
      pkgs.bashInteractive
    ];

    agents.sharedRules.shell-environment = shellEnvironmentRule;
  };
}
