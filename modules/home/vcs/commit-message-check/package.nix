{
  pkgs,
}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "commit-message-check";
  version = "0-unstable";

  src = ./.;

  nativeBuildInputs = [
    pkgs.python3
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 commit-message-check.py "$out/bin/commit-message-check"
    patchShebangs "$out/bin/commit-message-check"

    runHook postInstall
  '';

  doInstallCheck = true;

  installCheckPhase = ''
    runHook preInstallCheck

    checker="$out/bin/commit-message-check"
    stdout="$TMPDIR/commit-message-check.stdout"
    stderr="$TMPDIR/commit-message-check.stderr"

    expect_pass() {
      if ! "$checker" "$@" >"$stdout" 2>"$stderr"; then
        printf 'expected success, got failure:\n' >&2
        cat "$stderr" >&2
        exit 1
      fi
    }

    expect_error() {
      local expected="$1"
      shift

      if "$checker" "$@" >"$stdout" 2>"$stderr"; then
        printf 'expected failure, got success\n' >&2
        exit 1
      fi

      if ! grep -Fq "$expected" "$stderr"; then
        printf 'expected stderr to contain: %s\n' "$expected" >&2
        cat "$stderr" >&2
        exit 1
      fi
    }

    expect_pass <<'EOF'
    feat(vcs)!: add commit message checker

    Body line within limit.
    EOF

    expect_pass --types custom <<'EOF'
    custom: add checker path
    EOF

    expect_pass <<'EOF'
    docs: link to reference

    See https://example.com/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    EOF

    expect_pass <<'EOF'
    docs: mention inline code

    Use `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` when testing.
    EOF

    expect_error 'type must be one of' <<'EOF'
    noop: add checker
    EOF

    expect_error 'description must start with a lowercase letter' <<'EOF'
    feat: Add checker
    EOF

    expect_error 'description must not end with a period' <<'EOF'
    feat: add checker.
    EOF

    expect_error 'subject is' --subject-width 20 <<'EOF'
    feat: add a longer subject
    EOF

    expect_error 'line 3: body/footer line' <<'EOF'
    docs: add note

    This body line is intentionally written as ordinary prose that is longer than seventy-two characters.
    EOF

    expect_error 'line 3: body/footer line' --body-width 20 <<'EOF'
    docs: add note

    ordinary body line longer
    EOF

    runHook postInstallCheck
  '';
}
