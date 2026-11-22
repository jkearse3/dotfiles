{
  fzf,
  herdr-app,
  herdr-core,
  jjx,
  jujutsu,
  pkgs,
}:
pkgs.python3Packages.buildPythonApplication {
  pname = "herdr-jj-workspace";
  version = "0.0.0";
  pyproject = true;

  src = ./.;
  build-system = [ pkgs.python3Packages.setuptools ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  nativeCheckInputs = [
    jjx
    jujutsu
    pkgs.git
  ];

  # herdr-app and hc come last on PATH, so the profile's hc and tests' fake
  # executables win. Tests replace fzf through $HERDR_JJ_WORKSPACE_FZF_PATH.
  postFixup = ''
    wrapProgram "$out/bin/herdr-jj-workspace" \
      --set-default HERDR_JJ_WORKSPACE_FZF_PATH "${pkgs.lib.getExe fzf}" \
      --prefix PATH : "${
        pkgs.lib.makeBinPath [
          jjx
          jujutsu
        ]
      }" \
      --suffix PATH : "${
        pkgs.lib.makeBinPath [
          herdr-app
          herdr-core
        ]
      }"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HERDR_JJ_WORKSPACE="$out/bin/herdr-jj-workspace" \
      python3 -B -m unittest discover -s tests -p 'test_*.py'
    for command in add remove prompt-add prompt-remove; do
      "$out/bin/herdr-jj-workspace" "$command" --help > /dev/null
    done
    runHook postInstallCheck
  '';

  passthru.skill = ./skill;

  meta = {
    description = "Create and remove jj workspaces as Herdr app spaces";
    mainProgram = "herdr-jj-workspace";
  };
}
