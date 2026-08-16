{
  config,
  lib,
  pkgs,
  ...
}:
let
  onePasswordSsh = config.dotfiles.onePasswordSsh;
  sshSigner = pkgs.writeShellApplication {
    name = "ssh-sign-with-1password";
    text = ''
      export SSH_AUTH_SOCK=${lib.escapeShellArg onePasswordSsh.normalizedSocket}
      exec ${lib.getExe' pkgs.openssh "ssh-keygen"} "$@"
    '';
  };
  sshSignerProgram = "${sshSigner}/bin/ssh-sign-with-1password";

  identityType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.nonEmptyStr;
        description = "Commit author display name";
      };
      email = lib.mkOption {
        type = lib.types.nonEmptyStr;
        description = "Commit author email address";
      };
      signingKey = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Public SSH key used to sign commits, or null to disable signing";
      };
    };
  };

  repositoryScopeType = lib.types.submodule {
    options = {
      root = lib.mkOption {
        type = lib.types.nonEmptyStr;
        description = "Absolute or home-relative repository root";
      };
      identity = lib.mkOption {
        type = lib.types.nonEmptyStr;
        description = "Identity selected below this repository root";
      };
    };
  };

  policy = config.vcs.identityPolicy;
  identityExists = identity: builtins.hasAttr identity policy.identities;
  hasDefaultIdentity = policy.defaultIdentity != null && identityExists policy.defaultIdentity;
  defaultIdentity = if hasDefaultIdentity then policy.identities.${policy.defaultIdentity} else null;
  validRepositoryScopes = lib.filter (scope: identityExists scope.identity) policy.repositoryScopes;
  authorSettings = identity: {
    inherit (identity) name email;
  };
  gitSigningSettings =
    identity:
    if identity.signingKey == null then
      {
        commit.gpgSign = false;
        user.signingKey = "";
      }
    else
      {
        commit.gpgSign = true;
        user.signingKey = identity.signingKey;
      };
  jujutsuSigningSettings =
    identity:
    if identity.signingKey == null then
      {
        signing.backend = "none";
        git.sign-on-push = false;
      }
    else
      {
        signing = {
          backend = "ssh";
          key = identity.signingKey;
        };
        git.sign-on-push = true;
      };
  repositoryScopeRoots = map (scope: scope.root) policy.repositoryScopes;
  normalizedRepositoryScopeRoots = map (
    root:
    if lib.hasPrefix "~/" root then
      "${lib.removeSuffix "/" config.home.homeDirectory}/${lib.removePrefix "~/" root}"
    else
      root
  ) repositoryScopeRoots;
  invalidRepositoryScopeRoots = lib.filter (
    root:
    let
      components = lib.tail (lib.splitString "/" root);
    in
    !(lib.hasPrefix "~/" root || lib.hasPrefix "/" root)
    || lib.hasSuffix "/" root
    || lib.any (component: component == "" || component == "." || component == "..") components
    || lib.any (character: lib.hasInfix character root) [
      "*"
      "?"
      "["
      "]"
    ]
  ) repositoryScopeRoots;
  invalidRepositoryScopeIdentities = lib.unique (
    map (scope: scope.identity) (
      lib.filter (scope: !identityExists scope.identity) policy.repositoryScopes
    )
  );

  rootsHaveDeterministicPrecedence =
    roots:
    if roots == [ ] then
      true
    else
      let
        root = lib.head roots;
        remainingRoots = lib.tail roots;
      in
      lib.all (laterRoot: !lib.hasPrefix "${laterRoot}/" root) remainingRoots
      && rootsHaveDeterministicPrecedence remainingRoots;
in
{
  imports = [
    ./commit-message
    ./gh
    ./git
    ./jj
    ./lazygit
  ];

  options.vcs.identityPolicy = {
    identities = lib.mkOption {
      type = lib.types.attrsOf identityType;
      default = { };
      description = "Named complete commit identities";
    };
    defaultIdentity = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "Identity used outside repository scopes, or null to fail closed";
    };
    repositoryScopes = lib.mkOption {
      type = lib.types.listOf repositoryScopeType;
      default = [ ];
      description = ''
        Ordered repository identity scopes. Broader roots must precede nested
        roots so later, more-specific scopes have identical precedence in Git
        and Jujutsu.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = policy.defaultIdentity == null || hasDefaultIdentity;
        message = "vcs.identityPolicy.defaultIdentity must reference a defined identity";
      }
      {
        assertion = invalidRepositoryScopeIdentities == [ ];
        message = "vcs.identityPolicy.repositoryScopes reference undefined identities: ${lib.concatStringsSep ", " invalidRepositoryScopeIdentities}";
      }
      {
        assertion = invalidRepositoryScopeRoots == [ ];
        message = "vcs.identityPolicy repository roots must be canonical absolute or home-relative paths without trailing slashes or glob syntax: ${lib.concatStringsSep ", " invalidRepositoryScopeRoots}";
      }
      {
        assertion =
          lib.length normalizedRepositoryScopeRoots == lib.length (lib.unique normalizedRepositoryScopeRoots);
        message = "vcs.identityPolicy.repositoryScopes must not contain duplicate roots";
      }
      {
        assertion = rootsHaveDeterministicPrecedence normalizedRepositoryScopeRoots;
        message = "vcs.identityPolicy.repositoryScopes must order broader roots before nested roots";
      }
    ];

    vcs.identityPolicy = {
      identities.personal = lib.mkDefault {
        name = "Johnnie Kearse III";
        email = "jkearse3@gmail.com";
        signingKey = onePasswordSsh.githubSigningSelector;
      };
      defaultIdentity = lib.mkDefault "personal";
    };

    programs.git = {
      settings = lib.recursiveUpdate {
        gpg = {
          format = "ssh";
          ssh.program = sshSignerProgram;
        };
        user = {
          useConfigOnly = true;
        }
        // lib.optionalAttrs (defaultIdentity != null) (authorSettings defaultIdentity);
      } (lib.optionalAttrs (defaultIdentity != null) (gitSigningSettings defaultIdentity));
      includes = map (scope: {
        condition = "gitdir:${scope.root}/";
        contents = lib.recursiveUpdate {
          user = authorSettings policy.identities.${scope.identity};
        } (gitSigningSettings policy.identities.${scope.identity});
      }) validRepositoryScopes;
    };

    programs.jujutsu.settings =
      lib.recursiveUpdate
        {
          signing = {
            behavior = "drop";
            backends.ssh.program = sshSignerProgram;
          };
        }
        (
          lib.optionalAttrs (defaultIdentity != null) (
            lib.recursiveUpdate {
              user = authorSettings defaultIdentity;
            } (jujutsuSigningSettings defaultIdentity)
          )
        )
      // lib.optionalAttrs (validRepositoryScopes != [ ]) {
        "--scope" = map (
          scope:
          lib.recursiveUpdate {
            "--when".repositories = [ scope.root ];
            user = authorSettings policy.identities.${scope.identity};
          } (jujutsuSigningSettings policy.identities.${scope.identity})
        ) validRepositoryScopes;
      };
  };
}
