{ config, lib, ... }:
let
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
      };
      defaultIdentity = lib.mkDefault "personal";
    };

    programs.git = {
      settings.user = {
        useConfigOnly = true;
      }
      // lib.optionalAttrs (defaultIdentity != null) defaultIdentity;
      includes = map (scope: {
        condition = "gitdir:${scope.root}/";
        contents.user = policy.identities.${scope.identity};
      }) validRepositoryScopes;
    };

    programs.jujutsu.settings =
      lib.optionalAttrs (defaultIdentity != null) {
        user = defaultIdentity;
      }
      // lib.optionalAttrs (validRepositoryScopes != [ ]) {
        "--scope" = map (scope: {
          "--when".repositories = [ scope.root ];
          user = policy.identities.${scope.identity};
        }) validRepositoryScopes;
      };
  };
}
