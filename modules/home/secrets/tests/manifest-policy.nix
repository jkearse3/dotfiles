# Forced evaluation tests for the value-free manifest policy. Failure fixtures
# use deepSeq so lazy fields cannot hide an invalid declaration or scope.
{ lib }:
let
  evaluate = import ../manifestPolicy.nix { inherit lib; };
  rejects = text: !(builtins.tryEval (builtins.deepSeq (evaluate text) true)).success;
  fixture = ''
    [profiles.default]
    OPTIONAL = { required = false }
    IMPLICIT = { description = "Required unless explicitly false" }
    REQUIRED = { required = true }
    [profiles.other]
    OTHER = { required = true }
    OPTIONAL = { required = true }
    [scopes.optional]
    secrets = ["OPTIONAL"]
    [scopes.implicit]
    secrets = ["IMPLICIT"]
    [scopes.required]
    secrets = ["REQUIRED"]
    [scopes.mixed]
    secrets = ["OPTIONAL", "REQUIRED", "OTHER"]
    [scopes.inactive]
    secrets = ["OTHER"]
  '';
  policy = evaluate fixture;
  scopeFixture = members: ''
    [profiles.default]
    KEY = { required = false }
    [scopes.consumer]
    secrets = ${members}
  '';
  requirementFixture = requirement: ''
    [profiles.default]
    KEY = { required = ${requirement} }
    [scopes.consumer]
    secrets = ["KEY"]
  '';
in
lib.runTests {
  testScopeInventory = {
    expr = policy.scopeNames;
    expected = [
      "implicit"
      "inactive"
      "mixed"
      "optional"
      "required"
    ];
  };
  testAllProfileNamesAreUnique = {
    expr = policy.allSecretNames;
    expected = [
      "IMPLICIT"
      "OPTIONAL"
      "REQUIRED"
      "OTHER"
    ];
  };
  testOptionalInDefaultDespiteRequiredElsewhere = {
    expr = policy.scopes.optional;
    expected = {
      secretNames = [ "OPTIONAL" ];
      activeSecretNames = [ "OPTIONAL" ];
      requiresProvider = false;
    };
  };
  testOmittedRequirementIsRequired = {
    expr = policy.scopes.implicit.requiresProvider;
    expected = true;
  };
  testExplicitRequirementIsRequired = {
    expr = policy.scopes.required.requiresProvider;
    expected = true;
  };
  testMixedScopeUsesDefaultIntersection = {
    expr = policy.scopes.mixed;
    expected = {
      secretNames = [
        "OPTIONAL"
        "REQUIRED"
        "OTHER"
      ];
      activeSecretNames = [
        "OPTIONAL"
        "REQUIRED"
      ];
      requiresProvider = true;
    };
  };
  testEmptyActiveIntersectionNeedsNoProvider = {
    expr = policy.scopes.inactive;
    expected = {
      secretNames = [ "OTHER" ];
      activeSecretNames = [ ];
      requiresProvider = false;
    };
  };
  testManifestRequirementEditChangesPolicy = {
    expr = map (required: (evaluate (requirementFixture required)).scopes.consumer.requiresProvider) [
      "false"
      "true"
    ];
    expected = [
      false
      true
    ];
  };
  testMissingDefault = {
    expr = rejects ''
      [profiles.other]
      KEY = {}
      [scopes.consumer]
      secrets = ["KEY"]
    '';
    expected = true;
  };
  testMissingScopes = {
    expr = rejects ''
      [profiles.default]
      KEY = {}
    '';
    expected = true;
  };
  testEmptyScope = {
    expr = rejects (scopeFixture "[]");
    expected = true;
  };
  testMissingScopeMembers = {
    expr = rejects ''
      [profiles.default]
      KEY = {}
      [scopes.consumer]
    '';
    expected = true;
  };
  testDuplicateMembers = {
    expr = rejects (scopeFixture ''["KEY", "KEY"]'');
    expected = true;
  };
  testBlankMember = {
    expr = rejects (scopeFixture ''["KEY", ""]'');
    expected = true;
  };
  testWhitespaceMember = {
    expr = rejects (scopeFixture ''["KEY", " \t\n"]'');
    expected = true;
  };
  testUnknownMember = {
    expr = rejects (scopeFixture ''["KEY", "UNKNOWN"]'');
    expected = true;
  };
  testNonStringMember = {
    expr = rejects (scopeFixture ''["KEY", 42]'');
    expected = true;
  };
  testNonListMembers = {
    expr = rejects (scopeFixture ''"KEY"'');
    expected = true;
  };
  testStringRequirement = {
    expr = rejects (requirementFixture ''"false"'');
    expected = true;
  };
  testIntegerRequirement = {
    expr = rejects (requirementFixture "0");
    expected = true;
  };
  testListRequirement = {
    expr = rejects (requirementFixture "[]");
    expected = true;
  };
  testTableRequirement = {
    expr = rejects (requirementFixture "{}");
    expected = true;
  };
  testEmptyDefaultProfile = {
    expr =
      (evaluate ''
        [profiles.default]
        [profiles.other]
        KEY = {}
        [scopes.consumer]
        secrets = ["KEY"]
      '').scopes.consumer;
    expected = {
      secretNames = [ "KEY" ];
      activeSecretNames = [ ];
      requiresProvider = false;
    };
  };
  testMalformedInactiveRequirement = {
    expr = rejects ''
      [profiles.default]
      OPTIONAL = { required = false }
      [profiles.other]
      UNUSED = { required = "false" }
      [scopes.consumer]
      secrets = ["OPTIONAL"]
    '';
    expected = true;
  };
  testUnusedInvalidProfileIsStillRejected = {
    expr =
      (builtins.tryEval
        (evaluate (
          fixture
          + ''
            [profiles.unused]
            UNUSED = { required = "false" }
          ''
        )).scopeNames
      ).success;
    expected = false;
  };
  testUnusedInvalidScopeIsStillRejected = {
    expr =
      (builtins.tryEval
        (evaluate (
          fixture
          + ''
            [scopes.unused]
            secrets = ["UNKNOWN"]
          ''
        )).scopes.optional.requiresProvider
      ).success;
    expected = false;
  };
  testUnknownLauncherScopeIsRejected = {
    expr =
      (builtins.tryEval (
        import ../mkSecretEnvironmentWrapper.nix
          {
            inherit lib;
            manifest = ../../../../secretspec.toml;
            pkgs.writeShellApplication = application: application;
          }
          {
            name = "unknown-scope";
            environmentName = "undeclared-consumer";
            command = "/unused";
          }
      )).success;
    expected = false;
  };
  testRepositoryManifest = {
    expr = evaluate (builtins.readFile ../../../../secretspec.toml);
    expected = {
      scopeNames = [
        "opencode"
        "pi"
      ];
      allSecretNames = [ "EXA_API_KEY" ];
      scopes = {
        opencode = {
          secretNames = [ "EXA_API_KEY" ];
          activeSecretNames = [ "EXA_API_KEY" ];
          requiresProvider = false;
        };
        pi = {
          secretNames = [ "EXA_API_KEY" ];
          activeSecretNames = [ "EXA_API_KEY" ];
          requiresProvider = false;
        };
      };
    };
  };
}
