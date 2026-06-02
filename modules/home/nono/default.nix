{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Upstream nono 0.53.0's own integration test suite refuses to grant `/nix`
  # to the sandbox under test, because the Nix build sandbox mounts the
  # package's working tree under `/nix/var/nix/builds/...`, which overlaps
  # nono's "protected state root" guard. The failure is internal to nono's
  # own checkPhase and is unrelated to the wrapper code below. Skip checks
  # locally; upstream remains unchanged.
  nono = pkgs.nono.overrideAttrs (_: {
    doCheck = false;
  });
  mkNonoWrapper = import ./mkNonoWrapper.nix {
    pkgs = pkgs // {
      inherit nono;
    };
    inherit lib;
  };
  profile = {
    meta = {
      name = "coding-agents";
      description = "Shared sandbox profile for all coding agents on this machine — opencode, claude, and any future tools";
    };
    extends = "default";
    groups.include = [
      # Language runtimes let agents inspect and run project-local tooling across common stacks.
      "rust_runtime"
      "node_runtime"
      "go_runtime"
      "python_runtime"

      # User-tool groups cover operator-installed CLIs that agents commonly discover or invoke.
      "user_tools"
      "homebrew_macos"

      # Nix and VCS baseline needed for Nix-built binaries, repo metadata, and safe unlink behavior.
      "nix_runtime"
      "git_config"
      "unlink_protection"

      # Agent-specific macOS support for caches and Claude's Keychain-backed auth lifecycle.
      "user_caches_macos"
      "claude_code_macos"
    ];
    filesystem = {
      read = [
        # Read-only runtime inputs and discovery paths. These should not become write targets.
        "/nix/store"

        # Agent rules and skills are consumed read-only by coding agents.
        "${config.home.homeDirectory}/.agents"

        # Local profile overlays inherit generated profiles from this directory.
        "${config.home.homeDirectory}/.config/nono"

        # Claude probes this custom npm prefix for npm/yarn availability; installs use handoff.
        "${config.home.homeDirectory}/.npm-global"

        # Nix Home Manager symlinks configs from dotfiles; agents need to read the real paths.
        "${config.home.homeDirectory}/dotfiles"

        # Nix consults flake trust metadata before some evals; keep it readable but immutable.
        "${config.home.homeDirectory}/.local/share/nix"

        # Neovim config for inline editing from the sandbox.
        "${config.home.homeDirectory}/.config/nvim"
      ];
      allow = [
        # Writable state for Nix, fish, and jj workflows used during agent sessions.
        "${config.home.homeDirectory}/.cache/nix"
        "${config.home.homeDirectory}/.local/share/fish"
        "${config.home.homeDirectory}/.config/jj"

        # Neovim data, state, and cache for inline editing from the sandbox.
        "${config.home.homeDirectory}/.cache/nvim"
        "${config.home.homeDirectory}/.local/share/nvim"
        "${config.home.homeDirectory}/.local/state/nvim"

        # opencode config, cache, state, and data directories.
        "${config.home.homeDirectory}/.config/opencode"
        "${config.home.homeDirectory}/.cache/opencode"
        "${config.home.homeDirectory}/.local/share/opencode"
        "${config.home.homeDirectory}/.local/share/opentui"
        "${config.home.homeDirectory}/.local/state/opencode"
        "${config.home.homeDirectory}/.opencode"

        # Claude writes conversations, projects, backups, and relocated global config here.
        "${config.home.homeDirectory}/.claude"

        # Tools need the per-session temp directory for sockets, scratch files, and caches.
        "$TMPDIR"
      ];
      bypass_protection = [
        # Bypass only lifts nono deny-policy blocks; each path still needs a matching grant below.
        "${config.home.homeDirectory}/.agents"

        # SSH metadata lives under deny_credentials, so file-level grants need matching bypasses.
        "${config.home.homeDirectory}/.ssh/config"
        "${config.home.homeDirectory}/.ssh/known_hosts"
      ];
      read_file = [
        # SSH config is non-secret metadata. Private keys remain denied.
        "${config.home.homeDirectory}/.ssh/config"
      ];
      allow_file = [
        # SSH may append host keys; authentication itself goes through the injected SSH_AUTH_SOCK.
        "${config.home.homeDirectory}/.ssh/known_hosts"
      ];
      suppress_save_prompt = [
        # Suppress save-profile suggestions for the entire home directory. Agents probe
        # many denied dotfiles and Application Support paths every run; this silences the
        # recurring prompt across the whole subtree. Matching is by subtree, so this
        # subsumes the browser-data paths (Arc, Brave, Chromium, Chrome, Edge, Vivaldi,
        # Opera) that remain denied by deny_browser_data_macos. Enforcement is unchanged:
        # suppression only hides the suggestion; it never grants access or removes a deny.
        "${config.home.homeDirectory}"

        # Node.js and Claude probe Linux home-discovery paths. `/home` does not exist on macOS;
        # suppressing it only removes the recurring save-profile suggestion.
        "/home"
      ];
    };
    rollback = {
      exclude_patterns = [
        # Generated dependency/build outputs would make rollback snapshots noisy and large.
        "node_modules"
        "target"
        "__pycache__"
        "result"
      ];
      exclude_globs = [
        # File-level generated artifacts paired with the directory/name exclusions above.
        "*.pyc"
        "result-*"
      ];
    };

    # The repository cwd is the intended project write boundary; wider home access stays explicit.
    workdir.access = "readwrite";
  };
in
{
  _module.args.mkNonoWrapper = mkNonoWrapper;

  home.packages = [ nono ];

  home.file.".config/nono/profiles/coding-agents.json" = {
    source = pkgs.runCommandLocal "coding-agents.json" {
      nativeBuildInputs = [ pkgs.jq ];
      json = builtins.toJSON profile;
      passAsFile = [ "json" ];
    } "jq . $jsonPath > $out";
  };
}
