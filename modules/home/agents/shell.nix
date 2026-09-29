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
  # The tools the rule promises. Other home modules, mostly `modules/home/shell`,
  # install them; the assertion below keeps the lists agreeing.
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
  otherTools = [
    {
      package = pkgs.ripgrep;
      commands = "rg (ripgrep)";
    }
    {
      package = pkgs.fd;
      commands = "fd";
    }
    {
      package = pkgs.jq;
      commands = "jq";
    }
    {
      package = pkgs.yq-go;
      commands = "yq (mikefarah's Go yq)";
    }
    {
      package = pkgs.difftastic;
      commands = "difft (difftastic)";
    }
    {
      package = pkgs.tokei;
      commands = "tokei";
    }
    {
      package = pkgs.ast-grep;
      commands = "ast-grep";
    }
    {
      package = pkgs.hyperfine;
      commands = "hyperfine";
    }
    {
      package = pkgs.moreutils-without-parallel;
      commands = "sponge, ts, chronic (moreutils)";
    }
  ];
  missingTools = lib.filter (tool: !(lib.elem tool.package config.home.packages)) (
    gnuTools ++ otherTools
  );

  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  formatToolList = lib.concatMapStringsSep "\n" (tool: "- ${tool.commands} ${tool.package.version}");
  gnuToolList = formatToolList gnuTools;
  otherToolList = formatToolList otherTools;

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
    availability matters, check `<tool> --version` first.${lib.optionalString isDarwin "\n\n${''
      On macOS these shadow the BSD versions in `/usr/bin`, so BSD forms such as
      `sed -i '''`, `stat -f`, and `date -j` fail. `tar` remains BSD tar.''}"}

    It also puts these tools on PATH:

    ${otherToolList}'';
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
        assertion = missingTools == [ ];
        message = "the shell-environment agent rule lists tools the home profile does not install: ${
          lib.concatMapStringsSep ", " (tool: tool.package.pname) missingTools
        }";
      }
    ];

    home.packages = [
      pkgs.bashInteractive
    ];

    agents.sharedRules.shell-environment = shellEnvironmentRule;
  };
}
