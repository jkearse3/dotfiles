# Evaluates value-free SecretSpec TOML text for launchers pinned to the default
# profile. Validation covers every profile and scope before any policy is returned.
# No provider configuration or secret values are read. Invalid policy throws an
# assertion error; only an explicit boolean required = false makes a secret optional.
{ lib }:
manifestText:
let
  manifest = builtins.fromTOML manifestText;
  profiles = manifest.profiles or { };
  scopes = manifest.scopes or { };

  # Scope membership includes declarations from every profile; active membership
  # includes only the fixed default profile. These names also define the boundary
  # for removing excluded inherited secrets on launches without a provider.
  # scopeNames is sorted; allSecretNames is unique in sorted profile/name order.
  # Each scope preserves TOML member order and requires a provider exactly when
  # at least one active secret is required (never for an empty intersection).
  policy = {
    scopeNames = builtins.attrNames scopes;
    allSecretNames = lib.unique (
      lib.concatMap (profile: builtins.attrNames profiles.${profile}) (builtins.attrNames profiles)
    );
    scopes = lib.mapAttrs (
      _: scope:
      let
        activeSecretNames = builtins.filter (name: builtins.hasAttr name profiles.default) scope.secrets;
      in
      {
        secretNames = scope.secrets;
        inherit activeSecretNames;
        requiresProvider = builtins.any (name: profiles.default.${name}.required or true) activeSecretNames;
      }
    ) scopes;
  };

  validProfiles = lib.all (
    profileName:
    let
      profile = profiles.${profileName};
    in
    assert lib.assertMsg (builtins.isAttrs profile)
      "manifestPolicy: profile '${profileName}' must contain secret declarations";
    lib.all (
      secretName:
      let
        declaration = profile.${secretName};
      in
      assert lib.assertMsg (builtins.isAttrs declaration)
        "manifestPolicy: secret '${profileName}.${secretName}' must be a declaration";
      lib.assertMsg (builtins.isBool (
        declaration.required or true
      )) "manifestPolicy: required for '${profileName}.${secretName}' must be a boolean"
    ) (builtins.attrNames profile)
  ) (builtins.attrNames profiles);

  validScopes = lib.all (
    scopeName:
    let
      scope = scopes.${scopeName};
      members = scope.secrets or [ ];
    in
    assert lib.assertMsg (builtins.isAttrs scope)
      "manifestPolicy: scope '${scopeName}' must contain a secrets list";
    assert lib.assertMsg (
      builtins.isList members && members != [ ]
    ) "manifestPolicy: scope '${scopeName}' must contain a nonempty secrets list";
    assert lib.assertMsg (lib.all (
      name: builtins.isString name && builtins.match "[[:space:]]*" name == null
    ) members) "manifestPolicy: scope '${scopeName}' members must be nonblank secret names";
    assert lib.assertMsg (
      builtins.length (lib.unique members) == builtins.length members
    ) "manifestPolicy: scope '${scopeName}' contains duplicate secret names";
    lib.assertMsg (lib.all (
      name: lib.elem name policy.allSecretNames
    ) members) "manifestPolicy: scope '${scopeName}' references an undeclared secret"
  ) (builtins.attrNames scopes);
in
assert lib.assertMsg (
  builtins.isAttrs profiles && profiles ? default
) "manifestPolicy: the default profile is required";
assert lib.assertMsg (
  builtins.isAttrs scopes && scopes != { }
) "manifestPolicy: at least one scope is required";
assert validProfiles;
assert validScopes;
policy
